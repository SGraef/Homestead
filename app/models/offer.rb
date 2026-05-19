# frozen_string_literal: true
# typed: true

# A time-bounded promotional offer from a third-party flyer aggregator
# (Marktguru today; design leaves room for more sources). Imported by
# {OfferSyncer}; surfaced by {OffersController}.
class Offer < ApplicationRecord
  belongs_to :household
  belongs_to :product, optional: true
  belongs_to :store,   optional: true

  validates :source, :external_id, :retailer_name, :title, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :external_id, uniqueness: { scope: %i[household_id source] }

  # Currently-running offers in a household.
  scope :current, ->(today = Date.current) {
    where("(valid_from IS NULL OR valid_from <= ?) AND " \
          "(valid_until IS NULL OR valid_until >= ?)", today, today)
  }

  scope :ordered, -> { order(valid_until: :asc, price_cents: :asc) }

  # @return [Integer, nil] percentage off vs. regular price, when known.
  def discount_percent
    return nil unless regular_price_cents.to_i.positive? && price_cents

    (((regular_price_cents - price_cents).to_f / regular_price_cents) * 100).round
  end

  # @return [Float] price in major currency units (EUR, USD…).
  def price
    price_cents / 100.0
  end
end
