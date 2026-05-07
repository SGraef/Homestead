# frozen_string_literal: true
# typed: true

# A named place inside a household where {StorageItem}s live. Households
# start with one Location per built-in kind (pantry, fridge, freezer,
# cellar, other) and can add as many custom ones as they want
# ("Garage Tiefkühltruhe", "Vorratskeller links", …). The `kind` enum is
# kept as a separate column so business logic that cares about the *type*
# of place (e.g., "is this a freezer? warn after 3 months") keeps working
# regardless of the user's display name.
class Location < ApplicationRecord
  KINDS = %w[pantry fridge freezer cellar other].freeze

  belongs_to :household
  has_many :storage_items, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 60 },
                   uniqueness: { scope: :household_id, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }

  scope :ordered, -> { order(:position, :name) }

  def freezer? = kind == "freezer"
end
