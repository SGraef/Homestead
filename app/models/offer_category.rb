# frozen_string_literal: true
# typed: true

# A user-editable offer-category bucket. The household-scoped list of
# these (with their keywords) drives {OfferCategorizer}.
#
# `position` is what controls match priority — brand-rich categories
# typically need to come first so e.g. "Milka Tafel Vollmilch" routes
# to *Süßigkeiten* via the `milka` keyword rather than *Milch & Käse*
# via the generic `vollmilch`.
class OfferCategory < ApplicationRecord
  belongs_to :household
  has_many :offer_category_keywords,
           -> { order(:keyword) },
           dependent:  :destroy,
           inverse_of: :offer_category

  validates :name, presence: true, length: { maximum: 80 },
                   uniqueness: { scope: :household_id, case_sensitive: false }
  validates :position, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :name) }
end
