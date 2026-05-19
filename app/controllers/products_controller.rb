# frozen_string_literal: true
# typed: true

class ProductsController < ApplicationController
  before_action :ensure_household
  before_action :set_product, only: %i[show edit update destroy]

  def index
    @products = policy_scope(current_household.products).order(:name)
  end

  def show
    authorize @product
  end

  def new
    @product = current_household.products.build(prefill_attrs)
    authorize @product
  end

  def create
    @product = current_household.products.build(product_params)
    authorize @product
    if @product.save
      redirect_to @product, notice: t("notices.product_saved")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @product
  end

  def update
    authorize @product
    if @product.update(product_params)
      redirect_to @product, notice: t("notices.product_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @product
    if @product.destroy
      redirect_to products_path, notice: t("notices.product_removed")
    else
      # Surface dependent-record errors (e.g. anything wired up with
      # restrict_with_error in the future) so the user sees *why* the
      # delete didn't go through instead of a silent no-op.
      msg = @product.errors.full_messages.to_sentence.presence ||
            t("notices.product_remove_failed")
      redirect_to @product, alert: msg
    end
  end

  # GET /products/scan -- the barcode-scanner UI
  def scan; end

  # POST /products/attach_barcode  ?product_id=…&barcode=…
  #
  # Used by the unknown-barcode card on /products/scan: the user scanned a
  # code that doesn't exist locally, picks an existing product (e.g.
  # "Butter") from a dropdown, and the scanned EAN is attached as an
  # alternate ProductBarcode to that product. No JS / inline scripts: the
  # form posts here directly with `product_id` in the body.
  def attach_barcode
    product = current_household.products.find(params[:product_id])
    authorize product, :update?

    pb = product.product_barcodes.build(
      barcode: params[:barcode],
      brand:   params[:brand].presence
    )
    if pb.save
      redirect_to product, notice: t("notices.barcode_added")
    else
      redirect_to scan_products_path, alert: pb.errors.full_messages.to_sentence
    end
  end

  # GET /products/search.json?name=...&brand=...
  #
  # Searches Open Food Facts (and OPF as a fallback) for products matching
  # the given name / brand. Used by the product form's "Search by name"
  # button to discover the barcode + canonical fields when the user only
  # knows what they're looking at, not its EAN.
  def search
    name  = params[:name].to_s.strip
    brand = params[:brand].to_s.strip
    candidates = BarcodeLookup.search(name: name, brand: brand, limit: 5)

    existing = current_household.products.where.not(barcode: nil).pluck(:barcode).to_set

    payload = candidates.map do |c|
      h = c.to_h
      h[:already_in_household] = existing.include?(c.barcode)
      h
    end

    render json: { candidates: payload }
  end

  # GET /products/lookup?barcode=...
  #
  # Three response shapes by request format:
  #
  #   turbo_stream: the scan UI updates `#scan-result` with a match / suggestion / unknown card
  #   json:         the product form's "fetch info" button consumes
  #                 { source: "local"|"remote"|"none", product?, suggestion? }
  #   html:         falls back to the scan page (e.g. someone visited the URL directly)
  def lookup
    code = params[:barcode].to_s.gsub(/\D/, "")
    @barcode = code
    @product = current_household.products.by_barcode(code).first if code.present?
    @remote  = BarcodeLookup.call(code) if code.present? && @product.nil?
    respond_to do |format|
      format.turbo_stream
      format.json { render json: lookup_payload }
      format.html { redirect_to scan_products_path }
    end
  end

  private

  def ensure_household
    return if current_household

    redirect_to new_household_path, alert: t("flash.create_household_first")
  end

  def set_product
    @product = current_household.products.find(params[:id])
  end

  def product_params
    raw = params.require(:product).permit(
      :name, :brand, :barcode, :unit, :category, :notes,
      product_barcodes_attributes: %i[id barcode brand quantity_text _destroy]
    )
    # Clearing the primary barcode: AR's barcode validation is
    # `allow_nil`, not `allow_blank`, so a "" from the form would fail
    # format. Normalize to nil up front.
    raw[:barcode] = nil if raw.key?(:barcode) && raw[:barcode].to_s.strip.empty?
    raw
  end

  # Whitelisted query-string fields the scanner uses to prefill the new-product
  # form after a remote barcode lookup.
  def prefill_attrs
    params.permit(:barcode, :name, :brand, :category, :unit).to_h.compact_blank
  end

  def lookup_payload
    if @product
      { source: "local",
        product: ProductSerializer.call(@product),
        edit_url: edit_product_path(@product) }
    elsif @remote
      { source: "remote", suggestion: @remote.to_h }
    else
      { source: "none", barcode: @barcode }
    end
  end
end
