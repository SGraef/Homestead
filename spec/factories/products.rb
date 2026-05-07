# frozen_string_literal: true
# typed: false

FactoryBot.define do
  factory :store do
    household
    sequence(:name) { |n| "Store #{n}" }
    chain           { "REWE" }
  end

  factory :product do
    household
    sequence(:name) { |n| "Product #{n}" }
    sequence(:barcode) { |n| (4_000_000_000_000 + n).to_s }
    unit            { "pcs" }
  end

  factory :price do
    product
    store { association :store, household: product.household }
    amount_cents { 199 }
    currency     { "EUR" }
    observed_on  { Date.current }
    source       { "manual" }
  end

  factory :storage_item do
    household
    product { association :product, household: household }
    quantity { 1 }

    # Tests may pass `location: "fridge"` (kind string) or a Location
    # record; both resolve to one of the household's locations. The
    # transient `location_kind` lets the factory grow more readable callers.
    transient { location_kind { nil } }

    location do
      household.locations.find_by(kind: location_kind || "pantry") ||
        household.locations.find_or_create_by!(name: location_kind || "pantry") { |l|
          l.kind = location_kind || "pantry"
        }
    end
  end

  factory :grocery_item do
    household
    product { association :product, household: household }
    quantity { 1 }
    status   { "needed" }
  end
end
