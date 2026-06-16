# frozen_string_literal: true

FactoryBot.define do
  factory :calendar_connection do
    household
    provider { "google" }
    status   { "disconnected" }
  end
end
