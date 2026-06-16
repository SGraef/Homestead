# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe CalendarSync::Google::Oauth do
  let(:household) { create(:household) }
  let(:connection) do
    create(:calendar_connection, household: household,
           client_id: "cid.apps.googleusercontent.com", client_secret: "csecret")
  end

  describe ".authorize_url" do
    it "builds a consent URL with the client, scope, offline access and state" do
      url = described_class.authorize_url(connection, redirect_uri: "https://h/cb", state: "st8")
      expect(url).to start_with("https://accounts.google.com/o/oauth2/v2/auth?")
      expect(url).to include("client_id=cid.apps.googleusercontent.com")
      expect(url).to include("access_type=offline")
      expect(url).to include("state=st8")
      expect(url).to include(CGI.escape("https://www.googleapis.com/auth/calendar"))
    end
  end

  describe ".exchange_code" do
    it "stores tokens and marks the connection connected" do
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { access_token: "atk", refresh_token: "rtk", expires_in: 3600 }.to_json)

      described_class.exchange_code(connection, code: "authcode", redirect_uri: "https://h/cb")

      connection.reload
      expect(connection.status).to eq("connected")
      expect(connection.access_token).to eq("atk")
      expect(connection.refresh_token).to eq("rtk")
      expect(connection.token_expires_at).to be > Time.current
    end

    it "raises on a non-2xx token response" do
      stub_request(:post, "https://oauth2.googleapis.com/token").to_return(status: 400, body: "{}")
      expect { described_class.exchange_code(connection, code: "bad", redirect_uri: "https://h/cb") }
        .to raise_error(CalendarSync::Google::Error)
    end
  end

  describe ".refresh!" do
    it "swaps in a fresh access token" do
      connection.update!(refresh_token: "rtk", access_token: "old", token_expires_at: 1.hour.ago)
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { access_token: "fresh", expires_in: 3600 }.to_json)

      described_class.refresh!(connection)
      expect(connection.reload.access_token).to eq("fresh")
      expect(connection.token_expired?).to be(false)
    end
  end
end
