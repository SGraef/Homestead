# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe BringConnection do
  let(:household) { create(:household) }

  it "encrypts access_token and refresh_token at rest (ciphertext != plaintext)" do
    conn = described_class.create!(
      household: household, bring_email: "a@example.com", bring_user_uuid: "u-1",
      country_code: "DE", access_token: "secret-access", refresh_token: "secret-refresh"
    )

    raw = ActiveRecord::Base.connection.select_one(
      "SELECT access_token, refresh_token FROM bring_connections WHERE id = #{conn.id}"
    )
    expect(raw["access_token"]).not_to include("secret-access")
    expect(raw["refresh_token"]).not_to include("secret-refresh")

    conn.reload
    expect(conn.access_token).to eq("secret-access")   # decrypts transparently
    expect(conn.refresh_token).to eq("secret-refresh")
  end
end
