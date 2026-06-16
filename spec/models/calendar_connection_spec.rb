# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe CalendarConnection do
  let(:household) { create(:household) }

  it "validates provider and status" do
    expect(build(:calendar_connection, provider: "bogus")).not_to be_valid
    expect(build(:calendar_connection, status: "bogus")).not_to be_valid
    expect(build(:calendar_connection)).to be_valid
  end

  it "encrypts the client secret and tokens at rest (ciphertext != plaintext)" do
    conn = create(:calendar_connection, household: household,
                  client_secret: "topsecret", access_token: "atk", refresh_token: "rtk")

    raw = ActiveRecord::Base.connection.select_one(
      "SELECT client_secret, access_token, refresh_token FROM calendar_connections WHERE id = #{conn.id}"
    )
    expect(raw["client_secret"]).not_to include("topsecret")
    expect(raw["access_token"]).not_to include("atk")
    expect(raw["refresh_token"]).not_to include("rtk")
    expect(conn.reload.client_secret).to eq("topsecret") # decrypts transparently
  end

  describe "#token_expired?" do
    it "is true only when the expiry has passed" do
      expect(build(:calendar_connection, token_expires_at: 1.hour.ago)).to be_token_expired
      expect(build(:calendar_connection, token_expires_at: 1.hour.from_now)).not_to be_token_expired
      expect(build(:calendar_connection, token_expires_at: nil)).not_to be_token_expired
    end
  end
end
