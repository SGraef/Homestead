# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "API v1 Products" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let!(:product)  { create(:product, household: household, barcode: "4006381333924") }

  describe "GET /api/v1/products/lookup" do
    it "returns the local product when the barcode is in the household" do
      get "/api/v1/products/lookup", params: { barcode: product.barcode }, headers: api_login(user)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["source"]).to eq("local")
      expect(body.dig("product", "id")).to eq(product.id)
      expect(body.dig("product", "prices")).to be_an(Array)
    end

    it "falls back to the upstream database for an unknown barcode" do
      stub_request(:get, %r{world\.openfoodfacts\.org/api/v2/product/9999999999999\.json})
        .to_return(status: 200,
                   headers: { "Content-Type" => "application/json" },
                   body: { status: 1, product: { product_name: "Mystery Snack",
                                                 brands: "Acme",
                                                 quantity: "200 g" } }.to_json)

      get "/api/v1/products/lookup", params: { barcode: "9999999999999" }, headers: api_login(user)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["source"]).to eq("remote")
      expect(body.dig("suggestion", "name")).to eq("Mystery Snack")
      expect(body.dig("suggestion", "unit")).to eq("g")
    end

    it "returns 404 when neither local nor remote sources have the barcode" do
      stub_request(:get, %r{world\.open(food|products)facts\.org})
        .to_return(status: 200, body: { status: 0 }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, %r{marktguru\.de/api/v1/products/searchByEan})
        .to_return(status: 200, body: { results: [] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      get "/api/v1/products/lookup", params: { barcode: "0000000000" }, headers: api_login(user)
      expect(response).to have_http_status(:not_found)
    end

    it "rejects unauthenticated callers" do
      get "/api/v1/products/lookup", params: { barcode: product.barcode }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/grocery_items/scan_purchase" do
    it "marks an existing needed item purchased and creates a storage item" do
      gi = create(:grocery_item, household: household, product: product)

      expect {
        post "/api/v1/grocery_items/scan_purchase",
             params: { barcode: product.barcode },
             headers: api_login(user)
      }.to change(StorageItem, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(gi.reload.status).to eq("purchased")
    end
  end
end
