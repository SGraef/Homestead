# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "GET /storage_items?location_id=…" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:product_a) { create(:product, household: household, name: "Milk") }
  let(:product_b) { create(:product, household: household, name: "Apple") }
  let(:fridge)    { household.locations.find_by!(kind: "fridge") }
  let(:pantry)    { household.locations.find_by!(kind: "pantry") }

  before do
    create(:storage_item, household: household, product: product_a, location: fridge)
    create(:storage_item, household: household, product: product_b, location: pantry)
    login_via_post(user)
  end

  it "shows every item without a filter" do
    get "/storage_items"
    expect(response.body).to include("Milk", "Apple")
  end

  it "filters by the given location" do
    get "/storage_items", params: { location_id: fridge.id }
    expect(response.body).to include("Milk")
    expect(response.body).not_to include(">Apple<")
  end

  it "ignores unknown location_ids (acts like 'all')" do
    get "/storage_items", params: { location_id: 999_999 }
    expect(response.body).to include("Milk", "Apple")
  end

  it "API: GET /api/v1/storage_items?location_id=… filters too" do
    get "/api/v1/storage_items",
        params: { location_id: fridge.id }, headers: api_login(user)
    body = JSON.parse(response.body)
    expect(body.size).to eq(1)
    expect(body.first["product_name"]).to eq("Milk")
  end

  it "API: GET /api/v1/storage_items?location_kind=… filters by kind" do
    get "/api/v1/storage_items",
        params: { location_kind: "fridge" }, headers: api_login(user)
    body = JSON.parse(response.body)
    expect(body.first["product_name"]).to eq("Milk")
  end
end
