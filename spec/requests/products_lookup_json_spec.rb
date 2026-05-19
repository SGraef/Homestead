# frozen_string_literal: true
# typed: false

require "rails_helper"

# JSON branch of GET /products/lookup, used by the product form's
# "Fetch info" button (BarcodeFetchController).
RSpec.describe "GET /products/lookup.json (web)" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  before do
    household
    login_via_post(user)
  end

  it "returns the existing product when the barcode is already in the household" do
    product = create(:product, household: household, barcode: "4006381333924")

    get "/products/lookup.json", params: { barcode: product.barcode }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["source"]).to eq("local")
    expect(body.dig("product", "id")).to eq(product.id)
    expect(body["edit_url"]).to eq("/products/#{product.id}/edit")
  end

  it "returns a remote suggestion when the barcode is unknown locally" do
    stub_request(:get, %r{world\.openfoodfacts\.org/api/v2/product/4006381333924\.json})
      .to_return(status: 200,
                 headers: { "Content-Type" => "application/json" },
                 body: { status: 1, product: { product_name: "Whole Milk",
                                               brands: "Acme", quantity: "1 L" } }.to_json)

    get "/products/lookup.json", params: { barcode: "4006381333924" }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["source"]).to eq("remote")
    expect(body.dig("suggestion", "name")).to eq("Whole Milk")
    expect(body.dig("suggestion", "unit")).to eq("l")
  end

  it "returns source: 'none' when neither local nor remote sources match" do
    stub_request(:get, %r{world\.open(food|products)facts\.org})
      .to_return(status: 200, body: { status: 0 }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{marktguru\.de/api/v1/products/searchByEan})
      .to_return(status: 200, body: { results: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    get "/products/lookup.json", params: { barcode: "0000000000" }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["source"]).to eq("none")
    expect(body["barcode"]).to eq("0000000000")
  end
end
