# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Calendar connection settings" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin) }

  describe "as an admin" do
    before { login_via_post(admin) }

    it "shows the settings page" do
      get calendar_connection_path
      expect(response).to have_http_status(:ok)
    end

    it "saves the Google OAuth client credentials" do
      patch calendar_connection_path, params: {
        calendar_connection: { client_id: "abc.apps.googleusercontent.com", client_secret: "shh" }
      }
      conn = household.reload.calendar_connection
      expect(conn.client_id).to eq("abc.apps.googleusercontent.com")
      expect(conn.client_secret).to eq("shh")
    end

    it "keeps the stored secret when the secret field is left blank" do
      household.create_calendar_connection!(provider: "google", client_id: "x", client_secret: "keepme")
      patch calendar_connection_path, params: {
        calendar_connection: { client_id: "y", client_secret: "" }
      }
      conn = household.reload.calendar_connection
      expect(conn.client_id).to eq("y")
      expect(conn.client_secret).to eq("keepme")
    end
  end

  describe "as a non-admin member" do
    let(:member) { create(:user) }

    before do
      Membership.create!(user: member, household: household, role: "member")
      login_via_post(member)
    end

    it "is denied" do
      get calendar_connection_path
      expect(response).to redirect_to(root_path)
    end
  end
end
