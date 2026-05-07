# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Bring::Client do
  let(:user)       { create(:user) }
  let(:household)  { create(:household, admin: user) }
  let(:connection) do
    BringConnection.create!(
      household:               household,
      bring_email:             "demo@example.com",
      bring_user_uuid:         "user-uuid-1",
      default_list_uuid:       "list-uuid-1",
      access_token:            "tok-current",
      refresh_token:           "refresh-1",
      access_token_expires_at: 30.minutes.from_now,
      country_code:            "DE"
    )
  end

  describe ".login" do
    it "exchanges email + password for tokens" do
      stub_request(:post, "https://api.getbring.com/rest/v2/bringauth")
        .with(body: hash_including("email" => "user@example.com"))
        .to_return(status: 200,
                   headers: { "Content-Type" => "application/json" },
                   body: { uuid: "u-1", email: "user@example.com",
                           bringListUUID: "l-1",
                           access_token: "a", refresh_token: "r",
                           expires_in: 3600 }.to_json)

      data = described_class.login(email: "user@example.com", password: "secret", country: "DE")
      expect(data["uuid"]).to eq("u-1")
      expect(data["bringListUUID"]).to eq("l-1")
    end

    it "raises AuthError on bad credentials" do
      stub_request(:post, "https://api.getbring.com/rest/v2/bringauth")
        .to_return(status: 401, body: "")
      expect {
        described_class.login(email: "x", password: "y")
      }.to raise_error(Bring::AuthError)
    end
  end

  describe "#push_item" do
    it "PUTs to the bound list with purchase=name" do
      stub = stub_request(:put, "https://api.getbring.com/rest/v2/bringlists/list-uuid-1")
             .with(body: hash_including("purchase" => "Milk"),
                   headers: hash_including("Authorization" => "Bearer tok-current",
                                           "X-BRING-USER-UUID" => "user-uuid-1"))
             .to_return(status: 204)

      described_class.new(connection).push_item(name: "Milk")
      expect(stub).to have_been_requested
    end

    it "raises AuthError on 401 and records the error WITHOUT scrubbing the token" do
      stub_request(:put, "https://api.getbring.com/rest/v2/bringlists/list-uuid-1")
        .to_return(status: 401, body: "Unauthorized")

      expect { described_class.new(connection).push_item(name: "Milk") }
        .to raise_error(Bring::AuthError, /401/)

      connection.reload
      expect(connection.access_token).to eq("tok-current")     # token preserved
      expect(connection.last_error).to include("401")
    end

    it "uses the connection's stored token_type instead of hard-coding Bearer" do
      connection.update!(token_type: "JWT")
      stub = stub_request(:put, "https://api.getbring.com/rest/v2/bringlists/list-uuid-1")
             .with(headers: hash_including("Authorization" => "JWT tok-current",
                                           "X-BRING-VERSION" => Bring::Client::CLIENT_VERSION))
             .to_return(status: 204)

      described_class.new(connection).push_item(name: "Milk")
      expect(stub).to have_been_requested
    end
  end

  describe "#remove_item" do
    it "PUTs recently=name" do
      stub = stub_request(:put, "https://api.getbring.com/rest/v2/bringlists/list-uuid-1")
             .with(body: hash_including("recently" => "Milk"))
             .to_return(status: 204)

      described_class.new(connection).remove_item(name: "Milk")
      expect(stub).to have_been_requested
    end
  end

  describe "#lists" do
    it "GETs the user's lists" do
      stub_request(:get, "https://api.getbring.com/rest/v2/bringusers/user-uuid-1/lists")
        .to_return(status: 200,
                   headers: { "Content-Type" => "application/json" },
                   body: { lists: [{ listUuid: "l-1", name: "Wohnung" }] }.to_json)

      lists = described_class.new(connection).lists
      expect(lists.first["name"]).to eq("Wohnung")
    end
  end
end
