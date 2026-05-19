# frozen_string_literal: true
# typed: true

# A pattern the household never wants to see in the {Offer} feed. Match
# is case-insensitive substring against {Offer#title}; both the
# {OfferSyncer} (drop-on-write) and {Household#offer_blocked?} (in-memory
# filter) consult these.
class OfferBlocklistEntry < ApplicationRecord
  belongs_to :household

  validates :pattern, presence: true, length: { maximum: 200 },
                      uniqueness: { scope: :household_id, case_sensitive: false }

  scope :ordered, -> { order(:pattern) }

  # Lowercased normalized form used by the matcher -- avoids re-running
  # `downcase` on every offer titled at sync time.
  def normalized
    pattern.to_s.strip.downcase
  end

  # Does any pattern in `patterns` match `title`?
  # @param patterns [Array<String>] already-downcased patterns
  # @param title [String]
  # @return [Boolean]
  def self.match?(patterns, title)
    return false if title.blank?

    needle = title.to_s.downcase
    patterns.any? { |p| p.present? && needle.include?(p) }
  end
end
