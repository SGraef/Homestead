# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Calendar connection OAuth flow" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin) }

  before { login_via_post(admin) }

  def configure!
    household.create_calendar_connection!(provider: "google",
                                          client_id: "cid.apps.googleusercontent.com", client_secret: "csecret")
  end

  describe "POST connect" do
    it "redirects to Google consent with a state when configured" do
      configure!
      post connect_calendar_connection_path
      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with("https://accounts.google.com/o/oauth2/v2/auth?")
      expect(response.location).to include("client_id=cid.apps.googleusercontent.com")
    end

    it "refuses when credentials aren't saved yet" do
      post connect_calendar_connection_path
      expect(response).to redirect_to(calendar_connection_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "GET callback" do
    before { configure! }

    it "exchanges the code, stores tokens and connects (valid state)" do
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { access_token: "atk", refresh_token: "rtk", expires_in: 3600 }.to_json)

      post connect_calendar_connection_path
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]

      get callback_calendar_connection_path, params: { code: "authcode", state: state }
      expect(response).to redirect_to(calendar_connection_path)
      expect(household.calendar_connection.reload.status).to eq("connected")
    end

    it "rejects a mismatched state (CSRF guard) and does not connect" do
      get callback_calendar_connection_path, params: { code: "authcode", state: "forged" }
      expect(response).to redirect_to(calendar_connection_path)
      expect(flash[:alert]).to be_present
      expect(household.calendar_connection.reload.status).to eq("disconnected")
    end
  end

  describe "connected: pick calendar + disconnect" do
    before do
      configure!
      household.calendar_connection.update!(status: "connected", access_token: "atk",
                                            refresh_token: "rtk", token_expires_at: 1.hour.from_now)
    end

    it "shows the calendar picker (calendarList fetched)" do
      stub_request(:get, "https://www.googleapis.com/calendar/v3/users/me/calendarList")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { items: [{ id: "primary", summary: "Family" }] }.to_json)

      get calendar_connection_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Family")
    end

    it "selects a calendar" do
      patch select_calendar_calendar_connection_path, params: { calendar_id: "primary" }
      expect(household.calendar_connection.reload.calendar_id).to eq("primary")
    end

    it "disconnects (clears tokens + status)" do
      delete disconnect_calendar_connection_path
      conn = household.calendar_connection.reload
      expect(conn.status).to eq("disconnected")
      expect(conn.access_token).to be_nil
      expect(conn.refresh_token).to be_nil
    end
  end
end
