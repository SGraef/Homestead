# frozen_string_literal: true
# typed: false

FactoryBot.define do
  factory :offer do
    household
    sequence(:external_id) { |n| "mg-#{n}" }
    source        { "marktguru" }
    retailer_name { "REWE" }
    title         { "Bio Vollmilch 1L" }
    brand         { "Alnatura" }
    price_cents   { 89 }
    currency      { "EUR" }
    valid_from    { Date.current }
    valid_until   { Date.current + 5 }
  end
end
