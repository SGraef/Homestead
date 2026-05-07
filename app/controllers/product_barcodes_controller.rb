# frozen_string_literal: true
# typed: true

# Manages alternate barcodes (brand variants) for a Product. Used from the
# product show page and from the scan flow's "Add to existing product"
# branch when an unknown barcode should join an existing type.
class ProductBarcodesController < ApplicationController
  before_action :ensure_household
  before_action :set_product

  def create
    barcode = @product.product_barcodes.build(barcode_params)
    authorize @product, :update?
    if barcode.save
      redirect_to @product, notice: t("notices.barcode_added")
    else
      redirect_to @product, alert: barcode.errors.full_messages.to_sentence
    end
  end

  def update
    barcode = @product.product_barcodes.find(params[:id])
    authorize @product, :update?
    if barcode.update(barcode_params)
      redirect_to @product, notice: t("notices.barcode_updated")
    else
      redirect_to @product, alert: barcode.errors.full_messages.to_sentence
    end
  end

  def destroy
    barcode = @product.product_barcodes.find(params[:id])
    authorize @product, :update?
    barcode.destroy
    redirect_to @product, notice: t("notices.barcode_removed")
  end

  private

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_product
    @product = current_household.products.find(params[:product_id])
  end

  def barcode_params
    params.require(:product_barcode).permit(:barcode, :brand, :quantity_text)
  end
end
