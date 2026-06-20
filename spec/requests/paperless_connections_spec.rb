# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Paperless connection settings" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin) }

  describe "as an admin" do
    before { login_via_post(admin) }

    it "shows the connect form when none exists" do
      get paperless_connection_path
      expect(response).to redirect_to(new_paperless_connection_path)
    end

    it "renders the new form" do
      get new_paperless_connection_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the settings page for an existing connection" do
      household.create_paperless_connection!(base_url: "https://p.lan", api_token: "tok")
      get paperless_connection_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("https://p.lan")
    end

    it "saves a new connection" do
      post paperless_connection_path, params: {
        paperless_connection: { base_url: "https://paperless.lan", api_token: "tok-1", verify_ssl: "1" }
      }
      conn = household.reload.paperless_connection
      expect(conn).to be_present
      expect(conn.base_url).to eq("https://paperless.lan")
      expect(conn.api_token).to eq("tok-1")
    end

    it "rejects a connection saved without an api token" do
      post paperless_connection_path, params: {
        paperless_connection: { base_url: "https://paperless.lan", api_token: "" }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(household.reload.paperless_connection).to be_nil
    end

    it "rejects an invalid base url" do
      post paperless_connection_path, params: {
        paperless_connection: { base_url: "nope", api_token: "tok-1" }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(household.reload.paperless_connection).to be_nil
    end

    it "keeps the stored token when the token field is blank" do
      household.create_paperless_connection!(base_url: "https://p.lan", api_token: "keepme")
      patch paperless_connection_path, params: {
        paperless_connection: { base_url: "https://p2.lan", api_token: "" }
      }
      conn = household.reload.paperless_connection
      expect(conn.base_url).to eq("https://p2.lan")
      expect(conn.api_token).to eq("keepme")
    end

    it "tests the connection" do
      household.create_paperless_connection!(base_url: "https://p.lan", api_token: "tok")
      stub_request(:get, "https://p.lan/api/ui_settings/").to_return(status: 200, body: "{}")
      post test_paperless_connection_path
      expect(response).to redirect_to(paperless_connection_path)
      expect(flash[:notice]).to be_present
    end

    it "surfaces a failed test" do
      household.create_paperless_connection!(base_url: "https://p.lan", api_token: "tok")
      stub_request(:get, "https://p.lan/api/ui_settings/").to_return(status: 401, body: "no")
      post test_paperless_connection_path
      expect(flash[:alert]).to be_present
    end

    it "disconnects" do
      household.create_paperless_connection!(base_url: "https://p.lan", api_token: "tok")
      expect { delete paperless_connection_path }.to change { household.reload.paperless_connection }.to(nil)
    end
  end

  describe "as a non-admin member" do
    let(:member) { create(:user) }

    before do
      Membership.create!(user: member, household: household, role: "member")
      login_via_post(member)
    end

    it "is denied" do
      get paperless_connection_path
      expect(response).to redirect_to(root_path)
    end
  end
end
