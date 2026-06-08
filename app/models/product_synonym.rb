# frozen_string_literal: true
# typed: false

# Alternate name a Product is known by — used by the receipt parser to
# match OCR'd line names like "MILCH 1L" to the canonical "Milch" product,
# without forcing the user to keep renaming things.
#
# Normalisation: lowercase, collapse whitespace, drop everything that
# isn't a letter, digit or space. So "Milch 1L", "MILCH 1L" and
# "milch-1l" all reduce to "milch 1l" for matching purposes.
class ProductSynonym < ApplicationRecord
  belongs_to :product

  validates :term, presence: true, length: { maximum: 200 }
  validates :normalized_term, presence: true
  validates :normalized_term,
            uniqueness: { scope: :product_id, case_sensitive: false }

  before_validation :set_normalized_term

  # Public so callers (Product.match_by_term, the receipt confirmer)
  # can normalise their input through exactly the same rules.
  def self.normalize(text)
    text.to_s
        .unicode_normalize(:nfkc)
        .downcase
        .gsub(/[^[:alnum:]\s]/, " ")
        .squeeze(" ")
        .strip
  end

  private

  def set_normalized_term
    self.normalized_term = self.class.normalize(term)
  end
end
