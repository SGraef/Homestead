# frozen_string_literal: true
# typed: false

class RecipeIngredient < ApplicationRecord
  belongs_to :recipe
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  validate  :product_must_match_household

  # Effective display unit: explicit override on the row, otherwise
  # the linked product's unit.
  def display_unit
    unit.presence || product&.unit
  end

  # How much of this ingredient is currently in storage (sum of
  # quantities across all StorageItem rows for the product). Useful
  # for the "do we have enough?" badge on the recipe page.
  # @return [BigDecimal]
  def on_hand
    product&.storage_items&.sum(:quantity).to_d
  end

  # @return [Boolean] true when storage covers the recipe's quantity.
  def covered?
    on_hand >= quantity.to_d
  end

  private

  def product_must_match_household
    return unless product && recipe && product.household_id != recipe.household_id

    errors.add(:product, :wrong_household)
  end
end
