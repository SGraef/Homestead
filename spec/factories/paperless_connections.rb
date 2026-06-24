# frozen_string_literal: true

FactoryBot.define do
  factory :paperless_connection do
    household
    base_url   { "https://paperless.example.test" }
    api_token  { "test-token-123" }
    verify_ssl { true }
  end
end
