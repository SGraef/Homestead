# frozen_string_literal: true
# typed: true

# An observed price for a {Product} at a specific {Store} on a specific date.
# Stored in minor units (cents) to avoid float drift.
class Price < ApplicationRecord
  belongs_to :product
  belongs_to :store

  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true, length: { is: 3 }
  validates :observed_on, presence: true
  # pack_quantity: how many of the product's unit this price covers
  # (e.g. 0.5 for a 500 g pack of a product whose unit is "kg", 6 for
  # a 6-pack of pcs). Must be positive; defaults to 1.
  validates :pack_quantity, numericality: { greater_than: 0 }
  validate  :store_must_match_household

  scope :recent, -> { order(observed_on: :desc) }

  # @return [BigDecimal]
  def amount
    BigDecimal(amount_cents.to_s) / 100
  end

  # @param value [Numeric, String]
  def amount=(value)
    self.amount_cents = (BigDecimal(value.to_s) * 100).to_i
  end

  # Price expressed in the product's "shelf-tag" unit (kg / l / piece).
  # See {Product::NORMALIZED_UNITS}. Returns nil when the product or its
  # unit is missing -- callers should fall back to the raw amount.
  #
  # Divides by pack_quantity so a €2.49 / 500 g pack reports as
  # €4.98 / kg rather than €2.49 / kg.
  # @return [BigDecimal, nil]
  def amount_per_normalized_unit
    return nil unless product && amount_cents
    qty = BigDecimal((pack_quantity || 1).to_s)
    return nil if qty.zero?

    (BigDecimal(amount_cents.to_s) * product.normalized_price_multiplier / 100) / qty
  end

  # @return [String, nil] "kg", "l", or "piece"
  def normalized_unit
    product&.normalized_unit
  end

  private

  def store_must_match_household
    return if product && store && product.household_id == store.household_id

    errors.add(:store, "must belong to the same household as the product")
  end
end
