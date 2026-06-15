# frozen_string_literal: true
# typed: false

class StorageItemsController < ApplicationController
  before_action :ensure_household
  before_action :set_item, only: %i[show edit update destroy decrement move]

  def index
    scope = policy_scope(current_household.storage_items)
            .includes(:product, :location)

    @location = lookup_location(params[:location_id])
    scope     = scope.where(location: @location) if @location

    @query = params[:q].to_s.strip
    scope  = filter_by_query(scope, @query) if @query.present?

    @items     = scope.order(:expires_on)
    @expiring  = @items.expiring_within(7)
    # Counts are unfiltered by `q` on purpose -- the chips are a
    # navigation aid, and dimming them based on the current search
    # would make a missed-match feel like a missing location.
    @counts    = current_household.storage_items.group(:location_id).count
    @counts.default = 0
    @locations = current_household.locations.ordered
  end

  def show
    authorize @item
  end

  def new
    @item = current_household.storage_items.build(
      quantity:    1,
      location_id: lookup_location(params[:location_id])&.id ||
                   current_household.default_storage_location.id
    )
    authorize @item
  end

  def edit
    authorize @item
  end

  def create
    @item = current_household.storage_items.build(item_params)
    authorize @item
    if @item.save
      # The scan page posts here with return_to=scan so the user
      # lands back on /products/scan ready to scan the next item
      # instead of bouncing through the storage index.
      target = params[:return_to] == "scan" ? scan_products_path : storage_items_path
      redirect_to target,
                  notice: t("notices.storage_added_named",
                            name: @item.product.name, qty: @item.quantity)
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    authorize @item
    if @item.update(item_params)
      redirect_to storage_items_path, notice: t("notices.storage_updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @item
    @item.destroy
    redirect_to storage_items_path, notice: t("notices.storage_removed")
  end

  # POST /storage_items/:id/decrement -- "I just used some of these".
  # Accepts an optional `quantity` param (defaults to 1 for the
  # single-tap "used one" case). Comma is accepted as a decimal
  # separator so German keyboards work without translation. When the
  # remaining quantity hits zero or below, the row is destroyed.
  def decrement
    authorize @item, :update?
    @location = lookup_location(params[:location_id])
    name      = @item.product.name

    raw_qty = params[:quantity].to_s.tr(",", ".")
    amount  = raw_qty.present? ? BigDecimal(raw_qty) : BigDecimal(1)

    if amount <= 0
      return redirect_to storage_items_path(redirect_filter),
                         alert: t("storage.decrement.errors.bad_quantity")
    end

    new_qty = (@item.quantity || 0) - amount

    if new_qty <= 0
      @item.destroy
      flash_msg = t("notices.storage_consumed", name: name)
    else
      @item.update!(quantity: new_qty)
      flash_msg = t("notices.storage_decremented", name: name, qty: new_qty)
    end

    redirect_to storage_items_path(redirect_filter), notice: flash_msg
  rescue ArgumentError
    redirect_to storage_items_path(redirect_filter),
                alert: t("storage.decrement.errors.bad_quantity")
  end

  # POST /storage_items/:id/move
  # Move `quantity` units of this storage row to a different Location. If
  # the target location already has a row for the same product, the
  # quantities are merged (and earlier expiry / frozen-on wins). Source
  # row is decremented; destroyed if it lands at zero.
  def move
    authorize @item, :update?

    target = current_household.locations.find_by(id: params[:to_location_id])
    raw_qty = params[:quantity].to_s.tr(",", ".")
    qty = raw_qty.present? ? BigDecimal(raw_qty) : @item.quantity

    if target.nil?
      return redirect_to(storage_items_path(redirect_filter),
                         alert: t("storage.move.errors.no_target"))
    end
    if target == @item.location
      return redirect_to(storage_items_path(redirect_filter),
                         alert: t("storage.move.errors.same_location"))
    end
    if qty <= 0 || qty > @item.quantity
      return redirect_to(storage_items_path(redirect_filter),
                         alert: t("storage.move.errors.bad_quantity"))
    end

    StorageItem.transaction do
      existing = current_household.storage_items
                                  .find_by(product: @item.product, location: target)
      if existing
        existing.update!(
          quantity:   existing.quantity + qty,
          expires_on: earlier_of(existing.expires_on, @item.expires_on),
          frozen_on:  pick_frozen_on(existing, @item, target)
        )
      else
        current_household.storage_items.create!(
          product:    @item.product,
          location:   target,
          quantity:   qty,
          expires_on: @item.expires_on,
          opened_on:  @item.opened_on,
          frozen_on:  target.freezer? ? (@item.frozen_on || Date.current) : nil
        )
      end

      if qty == @item.quantity
        @item.destroy
      else
        @item.update!(quantity: @item.quantity - qty)
      end
    end

    redirect_to storage_items_path(redirect_filter),
                notice: t("notices.storage_moved",
                          name: @item.product.name, location: target.name)
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to storage_items_path(redirect_filter),
                alert: e.message
  end

  # GET /storage_items/scan
  # Kiosk-style bulk-add page: open camera once, every detected barcode
  # POSTs to #scan_add and lands a row in the on-page log without a
  # navigation. Manual barcode entry fallback is on the page for codes
  # the camera can't read.
  def scan
    @location = lookup_location(params[:location_id]) ||
                current_household.default_storage_location
    @recent   = policy_scope(current_household.storage_items)
                .includes(:product, :location)
                .order(created_at: :desc)
                .limit(20)
  end

  # POST /storage_items/scan_add
  # Take a barcode + (optional) location_id, resolve to a household
  # product, create a StorageItem with quantity 1 in the default
  # location, return a Turbo Stream that prepends a row to #scan-log
  # and re-arms the scanner for the next code.
  def scan_add
    barcode  = params[:barcode].to_s.strip.gsub(/\D/, "")
    location = lookup_location(params[:location_id]) ||
               current_household.default_storage_location

    return render_scan_error(message: t("storage.scan.empty_barcode")) if barcode.empty?

    product = current_household.products.by_barcode(barcode).first
    if product.nil?
      return render_scan_error(barcode: barcode,
                               message: t("storage.scan.unknown_barcode", code: barcode))
    end

    @item = current_household.storage_items.create!(
      product:   product,
      quantity:  1,
      location:  location,
      # Frozen-on auto-stamps when the target is the freezer (mirrors
      # the existing storage create flow's location-aware behaviour).
      frozen_on: (location.freezer? ? Date.current : nil)
    )
    authorize @item, :create?

    @location = location
    render :scan_add, formats: :turbo_stream
  rescue ActiveRecord::RecordInvalid => e
    render_scan_error(barcode: barcode, message: e.message)
  end

  private

  # Substring match against product name OR brand. The products table
  # is utf8mb4_0900_ai_ci, so the LIKE is already case- and
  # accent-insensitive at the collation level -- no need to lowercase
  # or strip diacritics ourselves.
  def filter_by_query(scope, query)
    needle = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    scope.joins(:product)
         .where("products.name LIKE :n OR products.brand LIKE :n", n: needle)
  end

  def redirect_filter
    @location ? { location_id: @location.id } : {}
  end

  def lookup_location(id)
    return nil if id.blank?

    current_household.locations.find_by(id: id)
  end

  def earlier_of(a, b)
    return b if a.nil?
    return a if b.nil?

    [a, b].min
  end

  def pick_frozen_on(existing, source, target)
    return nil unless target.freezer?

    [existing.frozen_on, source.frozen_on].compact.min || Date.current
  end

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_item
    @item = current_household.storage_items.find(params[:id])
  end

  # Renders the scan-error partial via Turbo Stream so the page itself
  # doesn't navigate — the user keeps the camera open and tries again.
  def render_scan_error(message:, barcode: nil)
    @barcode = barcode
    @error   = message
    render :scan_error, formats: :turbo_stream, status: :unprocessable_content
  end

  def item_params
    params.require(:storage_item)
          .permit(:product_id, :quantity, :location_id, :expires_on, :opened_on, :frozen_on)
  end
end
