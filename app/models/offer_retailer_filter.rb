# frozen_string_literal: true
# typed: true

# A retailer the household wants to *include* in their offer feed. The
# combined set of these rows acts as an allow-list -- empty = "all
# retailers welcome", non-empty = "only these".
#
# The stored value matches either Marktguru's `retailer.name` (e.g.
# "REWE", "Lidl") or its `uniqueName` slug (e.g. "rewe", "lidl"),
# case-insensitively. Users can type whichever they remember; the
# matcher checks both fields on each offer.
class OfferRetailerFilter < ApplicationRecord
  belongs_to :household

  validates :retailer, presence: true, length: { maximum: 80 },
                       uniqueness: { scope: :household_id, case_sensitive: false }

  scope :ordered, -> { order(:retailer) }

  def normalized
    retailer.to_s.strip.downcase
  end

  # Does `data` pass the allow-list `filters`?
  # @param filters [Array<String>] already-downcased retailer tokens
  # @param data [Marktguru::Offers::OfferData]
  # @return [Boolean] true when filters are empty (no allow-list set)
  #   or when at least one filter matches the offer's retailer name or slug
  def self.allow?(filters, data)
    return true if filters.empty?

    needles = [data.retailer_name, data.retailer_slug]
              .compact
              .map { |s| s.to_s.downcase }

    filters.any? { |f| needles.include?(f) }
  end
end
