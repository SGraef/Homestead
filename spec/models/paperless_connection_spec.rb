# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe PaperlessConnection do
  let(:household) { create(:household) }

  it "encrypts the api_token at rest" do
    conn = create(:paperless_connection, household: household, api_token: "secret-tok")
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT api_token FROM paperless_connections WHERE id = #{conn.id}"
    )
    expect(raw).not_to include("secret-tok")
    expect(conn.reload.api_token).to eq("secret-tok")
  end

  describe "validations" do
    it "requires a base_url" do
      expect(build(:paperless_connection, base_url: "")).not_to be_valid
    end

    it "rejects a non-http base_url" do
      expect(build(:paperless_connection, base_url: "ftp://nope")).not_to be_valid
      expect(build(:paperless_connection, base_url: "not a url")).not_to be_valid
    end

    it "accepts http and https" do
      expect(build(:paperless_connection, base_url: "http://paperless.lan")).to be_valid
      expect(build(:paperless_connection, base_url: "https://paperless.lan")).to be_valid
    end
  end

  describe "#connected?" do
    it "is true with a url and token" do
      expect(build(:paperless_connection)).to be_connected
    end

    it "is false without a token" do
      expect(build(:paperless_connection, api_token: nil)).not_to be_connected
    end
  end

  describe "#normalized_base_url" do
    it "strips a trailing slash and whitespace" do
      conn = build(:paperless_connection, base_url: "  https://p.lan/  ")
      expect(conn.normalized_base_url).to eq("https://p.lan")
    end
  end

  describe "#document_url" do
    let(:conn) { build(:paperless_connection, base_url: "https://p.lan") }

    it "builds a deep link from the base url and id" do
      expect(conn.document_url(42)).to eq("https://p.lan/documents/42/")
    end

    it "returns nil without an id" do
      expect(conn.document_url(nil)).to be_nil
    end
  end

  describe "#default_tags_list" do
    it "splits, trims and de-dupes" do
      conn = build(:paperless_connection, default_tags: "homestead, bill ,homestead")
      expect(conn.default_tags_list).to eq(%w[homestead bill])
    end
  end
end
