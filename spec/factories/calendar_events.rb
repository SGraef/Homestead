# frozen_string_literal: true

FactoryBot.define do
  factory :calendar_event do
    household
    sequence(:title) { |n| "Event #{n}" }
    starts_at { Time.utc(2026, 6, 15, 12, 0) }
    source { "manual" }
  end
end
