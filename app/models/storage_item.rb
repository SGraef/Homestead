# frozen_string_literal: true
# typed: false

# A physical unit of a {Product} currently sitting in one of the household's
# {Location}s. Multiple storage rows for the same product (in different
# locations) are allowed -- a household can have eggs in the pantry AND the
# fridge, each with its own quantity / expiry / frozen-on.
class StorageItem < ApplicationRecord
  # Default "long enough in the freezer that we should warn about it"
  # threshold (3 months ≈ 90 days). Override via env if you want a tighter
  # or looser policy on quality.
  STALE_FREEZER_DAYS = ENV.fetch("FREEZER_STALE_DAYS", "90").to_i

  belongs_to :household
  belongs_to :product
  belongs_to :location

  # Back-compat: accept either a Location record or a kind string
  # ("fridge", "freezer", …) so legacy callers (factories, services that
  # pass `location: "pantry"`) keep working. Strings are resolved against
  # the household's locations by `kind`.
  def location=(value)
    if value.is_a?(String) && household
      super(household.locations.find_by(kind: value))
    else
      super
    end
  end

  validates :quantity, numericality: { greater_than: 0 }
  validate  :product_must_match_household
  validate  :location_must_match_household

  scope :expiring_within, ->(days) { where(expires_on: Date.current..(Date.current + days.days)) }
  scope :expired,         -> { where(expires_on: ...Date.current) }
  scope :in_freezer,      -> { joins(:location).where(locations: { kind: "freezer" }) }

  # Items that have been in the freezer for `days` or more. The "frozen on"
  # anchor is `frozen_on` if present, else `created_at` -- so legacy rows
  # imported before that column existed still produce sensible warnings.
  scope :stale_in_freezer, lambda { |days = STALE_FREEZER_DAYS|
    in_freezer.where(
      "COALESCE(storage_items.frozen_on, DATE(storage_items.created_at)) <= ?",
      days.days.ago.to_date
    )
  }

  # @return [String] the kind of location ("pantry" / "fridge" / "freezer" / …).
  def location_kind
    location&.kind
  end

  # @return [Boolean]
  def in_freezer?
    location_kind == "freezer"
  end

  # @return [Integer] days until expiry, negative if already expired, nil if no date set
  def days_until_expiry
    return nil unless expires_on

    (expires_on - Date.current).to_i
  end

  # @return [Integer, nil] days the item has been in the freezer (or nil if
  #   it isn't currently in one).
  def days_in_freezer
    return nil unless in_freezer?

    base = frozen_on || created_at&.to_date
    return nil unless base

    (Date.current - base).to_i
  end

  def stale_in_freezer?
    days = days_in_freezer
    days.present? && days >= STALE_FREEZER_DAYS
  end

  private

  def product_must_match_household
    return if product && product.household_id == household_id

    errors.add(:product, "must belong to the same household")
  end

  def location_must_match_household
    return if location && location.household_id == household_id

    errors.add(:location, "must belong to the same household")
  end
end
