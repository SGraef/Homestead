# frozen_string_literal: true
# typed: false

require "rails_helper"

# The API resolves the household from Household.current alone -- no
# X-Household-Id header or household_id param is consulted any more.
RSpec.describe "API v1 single-household resolution" do
  let(:user)        { create(:user) }
  let!(:household)  { create(:household, admin: user) }
  let!(:storage_item) { create(:storage_item, household: household) }

  it "scopes to Household.current without any header" do
    get "/api/v1/storage_items", headers: api_login(user)
    expect(response).to have_http_status(:ok)
    ids = JSON.parse(response.body).map { |r| r["id"] }
    expect(ids).to include(storage_item.id)
  end

  it "ignores a stale X-Household-Id header and still serves the sole household" do
    get "/api/v1/storage_items",
        headers: api_login(user).merge("X-Household-Id" => "999999")
    expect(response).to have_http_status(:ok)
    ids = JSON.parse(response.body).map { |r| r["id"] }
    expect(ids).to include(storage_item.id)
  end
end
