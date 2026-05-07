# frozen_string_literal: true
# typed: true

# A grocery store where products can be priced and bought. Each Store belongs
# to exactly one {Household} so that price comparisons stay tenant-scoped.
class Store < ApplicationRecord
  belongs_to :household
  has_many :prices, dependent: :destroy
  has_many :grocery_items, dependent: :nullify
  has_many :receipts,      dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :household_id, case_sensitive: false }
end
