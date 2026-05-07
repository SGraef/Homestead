# frozen_string_literal: true
# typed: true

# A Household is the top-level tenancy boundary in Pantria. All food storage,
# grocery and price data is owned by exactly one household.
class Household < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :stores, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :storage_items, dependent: :destroy
  has_many :grocery_items, dependent: :destroy
  has_many :receipts, dependent: :destroy
  has_many :locations, -> { ordered }, dependent: :destroy
  has_one  :bring_connection, dependent: :destroy

  after_create :seed_default_locations

  validates :name, presence: true, length: { maximum: 80 }
  validates :timezone, presence: true

  # @return [ActiveRecord::Relation<StorageItem>] items expiring within `days`.
  def expiring_storage(days: 7)
    storage_items.where(expires_on: Date.current..Date.current + days.days)
  end

  # @return [ActiveRecord::Relation<GroceryItem>] items still needed.
  def open_grocery_items
    grocery_items.where(status: "needed")
  end

  # @return [ActiveRecord::Relation<StorageItem>] every storage row
  #   currently sitting in the freezer.
  def freezer_items
    storage_items.in_freezer.includes(:product)
  end

  # @return [ActiveRecord::Relation<StorageItem>] freezer rows that have
  #   been in there past the configured stale threshold (default 3 months).
  def stale_freezer_items(days = StorageItem::STALE_FREEZER_DAYS)
    storage_items.stale_in_freezer(days).includes(:product)
  end

  # @return [Boolean] true if the household has wired up Bring! and we can
  #   actually push a grocery item to it.
  def bring_connected?
    bring_connection&.connected?
  end

  # @return [Location] the household's freezer-kind location (used by the
  #   /freezer page and homemade-food entry). Lazily creates one if the
  #   user deleted theirs.
  def freezer_location
    locations.find_by(kind: "freezer") ||
      locations.create!(name: "Tiefkühler", kind: "freezer")
  end

  # @return [Location]
  def default_storage_location
    locations.find_by(kind: "pantry") ||
      locations.ordered.first ||
      locations.create!(name: "Vorratskammer", kind: "pantry")
  end

  private

  def seed_default_locations
    Location::KINDS.each_with_index do |kind, i|
      locations.find_or_create_by!(name: kind) do |loc|
        loc.kind     = kind
        loc.position = i
      end
    end
  end
end
