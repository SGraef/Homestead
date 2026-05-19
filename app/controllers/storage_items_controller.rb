# frozen_string_literal: true
# typed: true

class StorageItemsController < ApplicationController
  before_action :ensure_household
  before_action :set_item, only: %i[show edit update destroy decrement move]

  def index
    scope = policy_scope(current_household.storage_items)
              .includes(:product, :location)

    @location = lookup_location(params[:location_id])
    scope     = scope.where(location: @location) if @location

    @items     = scope.order(:expires_on)
    @expiring  = @items.expiring_within(7)
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

  def create
    @item = current_household.storage_items.build(item_params)
    authorize @item
    if @item.save
      redirect_to storage_items_path, notice: t("notices.storage_added")
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
      redirect_to storage_items_path, notice: t("notices.storage_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @item
    @item.destroy
    redirect_to storage_items_path, notice: t("notices.storage_removed")
  end

  # POST /storage_items/:id/decrement -- "I just used one of these".
  def decrement
    authorize @item, :update?
    @location = lookup_location(params[:location_id])
    name = @item.product.name
    new_qty = (@item.quantity || 0) - 1

    if new_qty <= 0
      @item.destroy
      flash_msg = t("notices.storage_consumed", name: name)
    else
      @item.update!(quantity: new_qty)
      flash_msg = t("notices.storage_decremented", name: name, qty: new_qty)
    end

    redirect_to storage_items_path(redirect_filter), notice: flash_msg
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

  private

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
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_item
    @item = current_household.storage_items.find(params[:id])
  end

  def item_params
    params.require(:storage_item)
          .permit(:product_id, :quantity, :location_id, :expires_on, :opened_on, :frozen_on)
  end
end
