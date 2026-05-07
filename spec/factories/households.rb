# frozen_string_literal: true
# typed: false

FactoryBot.define do
  factory :household do
    sequence(:name) { |n| "Household #{n}" }
    timezone        { "UTC" }

    transient { admin { nil } }
    after(:create) do |h, ev|
      Membership.create!(user: ev.admin, household: h, role: "admin") if ev.admin
    end
  end

  factory :membership do
    user
    household
    role { "member" }
  end
end
