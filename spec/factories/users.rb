# frozen_string_literal: true
# typed: false

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name             { "Test User" }
    password         { "password123" }
    password_confirmation { "password123" }

    # Sorcery's `before_create :setup_activation` forces activation_state to
    # "pending" on create, so flip it after_create. Tests that want to
    # exercise the activation flow can use `:user, :pending`.
    after(:create) { |u| u.update_columns(activation_state: "active") }

    trait :pending do
      after(:create) { |u| u.update_columns(activation_state: "pending") }
    end
  end
end
