# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe BarcodeLookup do
  let(:barcode) { "4006381333924" }

  describe ".call" do
    it "returns a normalised result when Open Food Facts has the product" do
      stub_request(:get, "https://world.openfoodfacts.org/api/v2/product/#{barcode}.json")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            status: 1,
            product: {
              product_name: "Whole Milk",
              brands: "Local Dairy, Acme",
              categories_tags: %w[en:dairies en:milks],
              quantity: "1 L",
              image_front_url: "https://example.com/milk.jpg"
            }
          }.to_json
        )

      result = described_class.call(barcode)

      expect(result).to be_a(BarcodeLookup::Result)
      expect(result.source).to eq("open_food_facts")
      expect(result.name).to eq("Whole Milk")
      expect(result.brand).to eq("Local Dairy")
      expect(result.unit).to eq("l")
      expect(result.image_url).to eq("https://example.com/milk.jpg")
    end

    it "falls through to Open Products Facts when OFF has nothing" do
      stub_request(:get, "https://world.openfoodfacts.org/api/v2/product/#{barcode}.json")
        .to_return(status: 200, body: { status: 0 }.to_json,
                   headers: { "Content-Type" => "application/json" })

      stub_request(:get, "https://world.openproductsfacts.org/api/v2/product/#{barcode}.json")
        .to_return(status: 200,
                   headers: { "Content-Type" => "application/json" },
                   body: { status: 1, product: { product_name: "Dish Soap", brands: "Acme",
                                                 quantity: "500 ml" } }.to_json)

      result = described_class.call(barcode)
      expect(result.source).to eq("open_products_facts")
      expect(result.unit).to eq("ml")
    end

    it "returns nil when both sources miss" do
      %w[
        https://world.openfoodfacts.org/api/v2/product
        https://world.openproductsfacts.org/api/v2/product
      ].each do |base|
        stub_request(:get, "#{base}/#{barcode}.json")
          .to_return(status: 200, body: { status: 0 }.to_json,
                     headers: { "Content-Type" => "application/json" })
      end

      expect(described_class.call(barcode)).to be_nil
    end

    it "swallows network errors and returns nil" do
      stub_request(:get, %r{world\.openfoodfacts\.org}).to_timeout
      stub_request(:get, %r{world\.openproductsfacts\.org}).to_timeout
      expect(described_class.call(barcode)).to be_nil
    end
  end

  describe ".search" do
    it "queries Open Food Facts CGI search with name + brand and returns Result objects" do
      stub_request(:get, %r{world\.openfoodfacts\.org/cgi/search\.pl})
        .with(query: hash_including("search_terms" => "Vollmilch Acme",
                                    "brands_tags"  => "Acme",
                                    "json"         => "1"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            products: [
              { "code" => "4006381333924", "product_name" => "Vollmilch 1L",
                "brands" => "Acme", "quantity" => "1 L" },
              { "code" => "1111111111111", "product_name" => "Bio Vollmilch",
                "brands" => "Acme", "quantity" => "500 ml" }
            ]
          }.to_json
        )

      results = described_class.search(name: "Vollmilch", brand: "Acme", limit: 5)

      expect(results.size).to eq(2)
      expect(results.first).to have_attributes(
        source:  "open_food_facts",
        barcode: "4006381333924",
        name:    "Vollmilch 1L",
        unit:    "l"
      )
      expect(results.last.barcode).to eq("1111111111111")
    end

    it "falls back to Open Products Facts when OFF returns no products" do
      stub_request(:get, %r{world\.openfoodfacts\.org/cgi/search\.pl})
        .to_return(status: 200, body: { products: [] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      stub_request(:get, %r{world\.openproductsfacts\.org/cgi/search\.pl})
        .to_return(status: 200,
                   headers: { "Content-Type" => "application/json" },
                   body: { products: [
                     { "code" => "9000000000000", "product_name" => "Soap", "brands" => "X" }
                   ] }.to_json)

      results = described_class.search(name: "Soap")
      expect(results.size).to eq(1)
      expect(results.first.source).to eq("open_products_facts")
    end

    it "returns [] when both name and brand are empty (no upstream call)" do
      results = described_class.search(name: "", brand: "")
      expect(results).to eq([])
      expect(WebMock).not_to have_requested(:get, %r{openfoodfacts})
    end
  end
end
