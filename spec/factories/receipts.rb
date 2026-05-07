# frozen_string_literal: true
# typed: false

FactoryBot.define do
  factory :receipt do
    household
    user { association :user }
    status { "pending" }
    currency { "EUR" }

    after(:build) do |r|
      r.image.attach(
        io:           StringIO.new("fake-jpg"),
        filename:     "receipt.jpg",
        content_type: "image/jpeg"
      )
    end
  end
end
