# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Marktguru::Offers do
  let(:postcode) { "10115" }

  describe ".pull_all" do
    it "fans out across configured industries and dedupes by external_id" do
      stub_request(:get, %r{api\.marktguru\.de/api/v1/industries/supermaerkte/offers})
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { results: [
            { "id" => 1, "description" => "je 1 L",
              "product"  => { "name" => "Vollmilch" },
              "retailer" => { "name" => "REWE", "uniqueName" => "rewe" },
              "brand"    => { "name" => "Alnatura" },
              "price"    => 0.89, "oldPrice" => 1.19,
              "validFrom" => "2026-05-03T22:00:00Z",
              "validTo"   => "2026-05-09T21:59:00Z" },
            # Same external_id will reappear under another industry.
            { "id" => 2, "description" => "je 1 kg",
              "product"  => { "name" => "Bananen" },
              "retailer" => { "name" => "REWE", "uniqueName" => "rewe" },
              "price"    => 1.49 }
          ] }.to_json
        )
      stub_request(:get, %r{api\.marktguru\.de/api/v1/industries/discounter/offers})
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { results: [
            { "id" => 2, "description" => "je 1 kg",
              "product"  => { "name" => "Bananen" },
              "retailer" => { "name" => "Lidl" },
              "price"    => 0.99 }
          ] }.to_json
        )
      stub_request(:get, %r{api\.marktguru\.de/api/v1/industries/drogerie-gesundheit/offers})
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { results: [] }.to_json
        )

      results = described_class.pull_all(postal_code: postcode, page_size: 50)
      expect(results.size).to eq(2)
      milk = results.find { |r| r.external_id == "1" }
      expect(milk.price_cents).to eq(89)
      expect(milk.regular_price_cents).to eq(119)
      expect(milk.retailer_name).to eq("REWE")
      expect(milk.unit).to eq("l")
      expect(milk.valid_until).to eq(Date.new(2026, 5, 9))
    end

    it "sends X-ApiKey + browser-like Origin/Referer on every call" do
      stub_request(:get, %r{api\.marktguru\.de/api/v1/industries/.+/offers})
        .to_return(status: 200, body: { results: [] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      described_class.pull_all(postal_code: postcode)
      expect(WebMock).to have_requested(:get, %r{api\.marktguru\.de/api/v1/industries})
        .with(headers: { "X-Apikey" => Marktguru::Offers::API_KEY,
                          "Origin"  => "https://www.marktguru.de" }).at_least_once
    end

    it "honours an explicit `industries:` argument" do
      stub_request(:get, %r{api\.marktguru\.de/api/v1/industries/baumaerkte/offers})
        .to_return(status: 200, body: { results: [] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      described_class.pull_all(postal_code: postcode, industries: %w[baumaerkte])

      expect(WebMock).to have_requested(:get,
        %r{api\.marktguru\.de/api/v1/industries/baumaerkte/offers}).at_least_once
      expect(WebMock).not_to have_requested(:get,
        %r{api\.marktguru\.de/api/v1/industries/supermaerkte/offers})
    end

    it "returns [] for a blank postal code without firing any HTTP" do
      expect(described_class.pull_all(postal_code: "")).to eq([])
      expect(WebMock).not_to have_requested(:get, %r{marktguru})
    end

    it "swallows network errors and returns []" do
      stub_request(:get, %r{api\.marktguru}).to_timeout
      expect(described_class.pull_all(postal_code: postcode)).to eq([])
    end

    it "drops malformed rows without raising" do
      stub_request(:get, %r{api\.marktguru\.de/api/v1/industries/supermaerkte/offers})
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { results: [
            { "id" => nil, "product" => { "name" => "no id" }, "price" => 1.0 },
            { "id" => 7,   "product" => { "name" => "no price" } },
            { "id" => 8,   "price" => 1.0 }, # no name + no description
            { "id" => 9,   "product" => { "name" => "ok" },
              "retailer" => { "name" => "Edeka" }, "price" => 0.50 }
          ] }.to_json
        )
      stub_request(:get, %r{api\.marktguru\.de/api/v1/industries/(?:discounter|drogerie-gesundheit)/offers})
        .to_return(status: 200, body: { results: [] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      results = described_class.pull_all(postal_code: postcode)
      expect(results.map(&:external_id)).to eq(["9"])
    end
  end
end
