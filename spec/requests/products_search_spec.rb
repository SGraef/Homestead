# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "GET /products/search.json" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  # Force the household to materialise -- controllers redirect away when
  # the user has none, and a few example branches don't otherwise reference
  # `household` (which would lazily create it).
  before do
    household
    login_via_post(user)
  end

  it "returns candidates from Open Food Facts and flags ones already in the household" do
    create(:product, household: household, barcode: "4006381333924", name: "Existing")

    stub_request(:get, %r{world\.openfoodfacts\.org/cgi/search\.pl})
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          products: [
            { "code" => "4006381333924", "product_name" => "Vollmilch 1L",
              "brands" => "Acme", "quantity" => "1 L" },
            { "code" => "9999999999999", "product_name" => "Bio Milk",
              "brands" => "Acme", "quantity" => "1 L" }
          ]
        }.to_json
      )

    get "/products/search.json", params: { name: "Vollmilch", brand: "Acme" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["candidates"].size).to eq(2)

    existing  = body["candidates"].find { |c| c["barcode"] == "4006381333924" }
    candidate = body["candidates"].find { |c| c["barcode"] == "9999999999999" }

    expect(existing["already_in_household"]).to be true
    expect(candidate["already_in_household"]).to be false
    expect(candidate["name"]).to eq("Bio Milk")
  end

  it "returns an empty list when neither name nor brand is provided" do
    get "/products/search.json", params: {}

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["candidates"]).to eq([])
  end
end
