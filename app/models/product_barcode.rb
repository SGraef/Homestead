# frozen_string_literal: true
# typed: true

# An alternate (per-brand) barcode attached to a {Product}. The product's own
# `barcode` column still holds the "primary" code; rows here are everything
# else. Validation enforces uniqueness across the household so the same EAN
# can't simultaneously belong to two products.
class ProductBarcode < ApplicationRecord
  belongs_to :product

  validates :barcode,
            presence: true,
            format: { with: /\A\d{8,14}\z/ }
  validates :barcode, uniqueness: { scope: :product_id }
  validate  :barcode_unique_in_household

  before_validation { self.barcode = barcode&.gsub(/\D/, "")&.presence }

  private

  def barcode_unique_in_household
    return if barcode.blank?
    return unless product

    household_id = product.household_id
    return if household_id.blank?

    primary = Product.where(household_id: household_id, barcode: barcode)
                     .where.not(id: product_id)
                     .exists?
    if primary
      errors.add(:barcode, :taken)
      return
    end

    alternate = ProductBarcode.joins(:product)
                              .where(barcode: barcode)
                              .where(products: { household_id: household_id })
                              .where.not(id: id)
                              .where.not(product_id: product_id)
                              .exists?
    errors.add(:barcode, :taken) if alternate
  end
end
