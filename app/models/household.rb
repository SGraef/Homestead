# frozen_string_literal: true
# typed: false

# A Household owns all food storage, grocery and price data. Pantria runs
# single-household-per-instance: one deployment serves exactly one household,
# resolved via {Household.current}. The schema still carries `household_id`
# everywhere (kept for non-destructive upgrades), but there is only ever one
# active household per install.
class Household < ApplicationRecord
  # The sole household this instance serves. Defined as the oldest household
  # (lowest id) so that databases upgraded from the old multi-household schema
  # deterministically pick one canonical household without touching the others'
  # rows. Computed fresh on every call (never memoize at class level) so the
  # first-run sign-up that creates the household, and tests that build one, see
  # it immediately. Returns nil on a brand-new, empty database.
  #
  # @return [Household, nil]
  def self.current
    order(:id).first
  end

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy
  has_many :stores, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :storage_items, dependent: :destroy
  has_many :grocery_items, dependent: :destroy
  has_many :receipts, dependent: :destroy
  has_many :locations, -> { ordered }, dependent: :destroy
  has_one  :bring_connection, dependent: :destroy
  has_many :offers, dependent: :destroy
  has_many :offer_blocklist_entries, dependent: :destroy
  has_many :offer_retailer_filters, dependent: :destroy
  has_many :offer_watchlist_entries, dependent: :destroy
  has_many :offer_categories, -> { ordered }, dependent: :destroy
  has_many :inbound_email_sources, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :meal_plan_entries, dependent: :destroy
  has_many :todos, dependent: :destroy
  has_many :todo_comments, dependent: :destroy
  has_many :todo_follows, dependent: :destroy
  has_many :notifications, dependent: :destroy

  after_create :seed_default_offer_categories

  after_create :seed_default_locations

  validates :name, presence: true, length: { maximum: 80 }
  validates :timezone, presence: true
  # Loose validation: accepts DE 5-digit codes plus international formats
  # (alphanumeric + space + hyphen, up to 16 chars). Marktguru itself only
  # supports DE codes today; we keep the model permissive for future
  # adapters.
  validates :postal_code, allow_blank: true, length: { maximum: 16 },
                          format: { with: /\A[A-Z0-9 -]+\z/i }

  # Flaschenpost's product API is locked behind a region-specific
  # warehouse_id. Nullable -- households that don't set it just skip
  # the Flaschenpost source during sync.
  validates :flaschenpost_warehouse_id, allow_nil:    true,
                                        numericality: { only_integer: true, greater_than: 0 }

  # @return [ActiveRecord::Relation<StorageItem>] items expiring within `days`.
  def expiring_storage(days: 7)
    storage_items.where(expires_on: Date.current..(Date.current + days.days))
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

  def seed_default_offer_categories
    OfferCategorySeeder.call(self)
  rescue StandardError => e
    Rails.logger.warn("[Household] offer-category seed failed: #{e.class}: #{e.message}")
  end

  def seed_default_locations
    Location::KINDS.each_with_index do |kind, i|
      locations.find_or_create_by!(name: kind) do |loc|
        loc.kind     = kind
        loc.position = i
      end
    end
  end
end
