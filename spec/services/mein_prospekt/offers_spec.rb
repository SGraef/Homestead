# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe MeinProspekt::Offers do
  def api_body(offers)
    { searchResults: { contents: { offers: offers, brochures: [] },
                       metadata: { contentCount: { offer: offers.size } } } }.to_json
  end

  describe ".pull_all" do
    it "extracts offers from the search-API response and normalises them" do
      page1 = (1..24).map do |i|
        { "id"            => "id-#{i}",
          "publisherName" => "ALDI Nord",
          "publisherId"   => "DE-75",
          "title"         => "Mandeln #{i}",
          "prices"        => { "mainPrice" => 1.69, "secondaryPrice" => 0,
                                "priceByBaseUnit" => "1 kg = 11.27" },
          "offerImages"   => { "url" => { "normal" => "https://x/y-#{i}.jpg" } } }
      end

      stub_request(:get, %r{www\.meinprospekt\.de/api/search})
        .with(query: hash_including("query" => "ALDI Nord", "offset" => "0"))
        .to_return(status: 200, body: api_body(page1),
                   headers: { "Content-Type" => "application/json" })
      # Page 2: short (signals end of pagination).
      stub_request(:get, %r{www\.meinprospekt\.de/api/search})
        .with(query: hash_including("query" => "ALDI Nord", "offset" => "24"))
        .to_return(status: 200, body: api_body([{
          "id" => "id-25",
          "publisherName" => "ALDI Nord", "publisherId" => "DE-75",
          "title" => "Naturradler",
          "prices" => { "mainPrice" => 0.79, "secondaryPrice" => 1.15 }
        }]), headers: { "Content-Type" => "application/json" })

      result = described_class.pull_all
      expect(result.size).to eq(25)
      milk = result.find { |o| o.title == "Mandeln 1" }
      expect(milk).to have_attributes(
        retailer_name: "ALDI Nord",
        price_cents:   169,
        image_url:     "https://x/y-1.jpg",
        quantity_text: "1 kg = 11.27"
      )
      radler = result.find { |o| o.title == "Naturradler" }
      expect(radler.regular_price_cents).to eq(115)  # secondary > main
    end

    it "fans out across multiple `queries:` and dedupes by external_id" do
      stub_request(:get, %r{www\.meinprospekt\.de/api/search})
        .with(query: hash_including("query" => "Aldi Süd"))
        .to_return(status: 200, body: api_body([
          { "id" => "shared", "publisherName" => "Aldi Süd",
            "title" => "Brot", "prices" => { "mainPrice" => 1.0 } }
        ]), headers: { "Content-Type" => "application/json" })
      stub_request(:get, %r{www\.meinprospekt\.de/api/search})
        .with(query: hash_including("query" => "Tegut"))
        .to_return(status: 200, body: api_body([
          { "id" => "shared",  "publisherName" => "Tegut", "title" => "Brot",
            "prices" => { "mainPrice" => 0.99 } },
          { "id" => "tegut-2", "publisherName" => "Tegut", "title" => "Käse",
            "prices" => { "mainPrice" => 2.49 } }
        ]), headers: { "Content-Type" => "application/json" })

      result = described_class.pull_all(queries: %w[Aldi\ Süd Tegut])
      expect(result.map(&:external_id).sort).to eq(%w[shared tegut-2])
    end

    it "drops rows without an id, title, or price" do
      stub_request(:get, %r{www\.meinprospekt\.de/api/search})
        .to_return(status: 200, body: api_body([
          { "id" => nil, "title" => "x", "prices" => { "mainPrice" => 1.0 } },
          { "id" => "a", "title" => "",  "prices" => { "mainPrice" => 1.0 } },
          { "id" => "b", "title" => "ok"                                   },
          { "id" => "c", "title" => "good","prices" => { "mainPrice" => 1.0 } }
        ]), headers: { "Content-Type" => "application/json" })

      expect(described_class.pull_all.map(&:external_id)).to eq(["c"])
    end

    it "swallows network errors and returns []" do
      stub_request(:get, %r{www\.meinprospekt\.de}).to_timeout
      expect(described_class.pull_all).to eq([])
    end

    it "returns [] when given no queries and no env override" do
      stub_request(:get, %r{www\.meinprospekt\.de/api/search})
        .to_return(status: 200, body: api_body([]),
                   headers: { "Content-Type" => "application/json" })

      # Default queries fire ALDI Nord; just verify it doesn't raise and
      # short-circuits cleanly on empty results.
      expect(described_class.pull_all).to eq([])
    end
  end
end
