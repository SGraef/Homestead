# frozen_string_literal: true
# typed: true

class GroceryItemsController < ApplicationController
  before_action :ensure_household
  before_action :set_item, only: %i[show edit update destroy purchase]

  def index
    scope = policy_scope(current_household.grocery_items).includes(:product, :store)

    @show_purchased = params[:show_purchased] == "1"
    scope = scope.where(status: "needed") unless @show_purchased

    @items = scope.order(status: :asc, created_at: :desc)
    @purchased_count = current_household.grocery_items.where(status: "purchased").count
  end

  def show
    authorize @item
  end

  def new
    @item = current_household.grocery_items.build(quantity: 1)
    authorize @item
  end

  def create
    @item = current_household.grocery_items.build(item_params)
    authorize @item
    if @item.save
      redirect_to grocery_items_path, notice: t("notices.grocery_added")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @item
  end

  def update
    authorize @item
    if @item.update(item_params)
      redirect_to grocery_items_path, notice: t("notices.grocery_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @item
    @item.destroy
    redirect_to grocery_items_path, notice: t("notices.grocery_removed")
  end

  # PATCH /grocery_items/:id/purchase
  def purchase
    authorize @item, :update?
    @item.mark_purchased!(
      store: current_household.stores.find_by(id: params[:store_id]),
      paid_amount: params[:paid_amount],
      expires_on: params[:expires_on].presence,
      location: params[:location].presence || "pantry"
    )
    respond_to do |format|
      format.html { redirect_to grocery_items_path, notice: t("grocery.purchased") }
      format.turbo_stream
    end
  end

  # DELETE /grocery_items/purge_purchased
  # Bulk-remove every purchased row in the household. Each destroy fires the
  # standard callbacks (Bring sync, etc.) so the UI and Bring stay aligned.
  def purge_purchased
    items = current_household.grocery_items.where(status: "purchased")
    count = 0
    GroceryItem.transaction do
      items.find_each do |item|
        item.destroy
        count += 1
      end
    end
    redirect_to grocery_items_path, notice: t("grocery.purged", count: count)
  end

  # POST /grocery_items/scan_purchase
  # Quickly mark a needed item as purchased by scanning its barcode at the till.
  def scan_purchase
    barcode = params[:barcode].to_s.strip
    product = current_household.products.by_barcode(barcode).first
    if product.nil?
      redirect_to grocery_items_path, alert: t("grocery.scan_unknown", code: barcode) and return
    end

    item = current_household.grocery_items.needed.find_by(product: product) ||
           current_household.grocery_items.create!(product: product, quantity: 1)
    authorize item, :update?
    item.mark_purchased!(store: current_household.stores.find_by(id: params[:store_id]))

    redirect_to grocery_items_path, notice: t("grocery.purchased")
  end

  private

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_item
    @item = current_household.grocery_items.find(params[:id])
  end

  def item_params
    params.require(:grocery_item).permit(:product_id, :store_id, :quantity, :status)
  end
end
