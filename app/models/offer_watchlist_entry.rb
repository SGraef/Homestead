# frozen_string_literal: true
# typed: true

# Pattern the household is always watching for in the offer feed. When an
# offer's title contains any of these (case-insensitive substring), it
# gets sorted to the top of /offers and highlighted. Doesn't change what
# gets synced -- only how the index page renders.
class OfferWatchlistEntry < ApplicationRecord
  belongs_to :household

  validates :pattern, presence: true, length: { maximum: 200 },
                      uniqueness: { scope: :household_id, case_sensitive: false }

  scope :ordered, -> { order(:pattern) }

  # Lowercased trimmed pattern used by the matcher.
  def normalized
    pattern.to_s.strip.downcase
  end

  # Does any pattern in `patterns` match `title`?
  # @param patterns [Array<String>] already-downcased patterns
  # @param title [String]
  def self.match?(patterns, title)
    return false if title.blank?

    needle = title.to_s.downcase
    patterns.any? { |p| p.present? && needle.include?(p) }
  end
end
