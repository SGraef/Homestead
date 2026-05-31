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

  # Can the "Used" button safely decrement storage for this row?
  # We refuse the conversion when the row's unit override doesn't
  # match the product's storage unit -- "4 EL Öl" vs an oil row
  # stored in ml has no defensible auto-conversion, and silently
  # subtracting `4` from the ml row would corrupt inventory.
  def consumable?
    return true if unit.blank?

    unit.to_s.casecmp(product&.unit.to_s).zero?
  end

  ConsumeResult = Struct.new(:consumed, :short, :ok, keyword_init: true) do
    def ok? = ok
    def short? = (short || 0).positive?
  end

  # Decrement storage for this ingredient's product by `quantity`.
  # Walks storage_items in expires-on-soonest order so the
  # soonest-to-expire row is drained first. Drops storage rows that
  # reach zero. Returns a ConsumeResult: how much actually came off
  # and how much we came up short.
  def consume_from_storage!
    return ConsumeResult.new(consumed: 0, short: 0, ok: false) unless consumable? && product

    needed   = quantity.to_d
    consumed = BigDecimal(0)

    # NULL expires_on lands last so dated items get used up first.
    items = product.storage_items
                   .order(Arel.sql("expires_on IS NULL"), :expires_on, :id)
                   .to_a

    StorageItem.transaction do
      items.each do |item|
        break if needed <= 0

        take      = [item.quantity.to_d, needed].min
        remaining = item.quantity.to_d - take

        if remaining <= 0
          item.destroy!
        else
          item.update!(quantity: remaining)
        end

        needed   -= take
        consumed += take
      end
    end

    ConsumeResult.new(consumed: consumed, short: needed, ok: true)
  end

  private

  def product_must_match_household
    return unless product && recipe && product.household_id != recipe.household_id

    errors.add(:product, :wrong_household)
  end
end
