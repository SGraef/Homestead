# frozen_string_literal: true
# typed: true

# One keyword inside an {OfferCategory}. Stored downcased + trimmed so
# the classifier's substring match doesn't have to renormalise on
# every hit. Uniqueness is scoped to the parent category, so the same
# keyword can sit under multiple categories in different households
# (and even in different categories within one household if the user
# really wants — useful for shared brand names like "Bio").
class OfferCategoryKeyword < ApplicationRecord
  belongs_to :offer_category, inverse_of: :offer_category_keywords

  validates :keyword, presence: true, length: { maximum: 80 },
                      uniqueness: { scope: :offer_category_id, case_sensitive: false }

  before_validation :normalise_keyword

  private

  def normalise_keyword
    self.keyword = keyword.to_s.strip.downcase if keyword
  end
end
