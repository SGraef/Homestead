# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "API v1 Sessions" do
  let(:user) { create(:user) }

  it "issues a token on valid credentials" do
    post "/api/v1/sessions", params: { email: user.email, password: "password123" }
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["token"]).to be_present
    expect(ApiToken.authenticate(body["token"])).to be_present
  end

  it "rejects bad credentials" do
    post "/api/v1/sessions", params: { email: user.email, password: "wrong" }
    expect(response).to have_http_status(:unauthorized)
  end
end
