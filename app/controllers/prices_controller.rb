# frozen_string_literal: true
# typed: true

class PricesController < ApplicationController
  before_action :ensure_household
  before_action :set_product
  before_action :set_price, only: %i[edit update destroy]

  def index
    @prices = @product.prices.includes(:store).recent
  end

  def new
    @price = @product.prices.build(observed_on: Date.current)
    authorize @price
  end

  def create
    @price = @product.prices.build(price_params)
    authorize @price
    if @price.save
      redirect_to product_prices_path(@product), notice: t("notices.price_recorded")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @price
  end

  def update
    authorize @price
    if @price.update(price_params)
      redirect_to product_prices_path(@product), notice: t("notices.price_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @price
    @price.destroy
    redirect_to product_prices_path(@product), notice: t("notices.price_removed")
  end

  private

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_product
    @product = current_household.products.find(params[:product_id])
  end

  def set_price
    @price = @product.prices.find(params[:id])
  end

  def price_params
    params.require(:price).permit(:store_id, :amount, :currency, :observed_on, :source, :pack_quantity)
  end
end
