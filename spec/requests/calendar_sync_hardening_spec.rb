# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Calendar sync hardening (PR5)" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin, timezone: "Europe/Berlin") }
  let!(:connection) do
    household.create_calendar_connection!(provider: "google", status: "connected",
                                          access_token: "atk", token_expires_at: 1.hour.from_now, calendar_id: "primary")
  end

  before { login_via_post(admin) }

  describe "recurring events are read-only" do
    let!(:recurring) do
      connection.calendar_events.create!(household: household, title: "Standup", recurring: true,
                                         sync_origin: "remote", remote_id: "r1", starts_at: Time.utc(2026, 6, 20, 7))
    end

    it "blocks editing a recurring event" do
      get edit_calendar_event_path(recurring)
      expect(response).to redirect_to(calendar_path)
      expect(flash[:alert]).to eq(I18n.t("calendar.recurring_readonly"))
    end

    it "blocks updating a recurring event" do
      patch calendar_event_path(recurring), params: { calendar_event: { title: "Hacked" } }
      expect(response).to redirect_to(calendar_path)
      expect(recurring.reload.title).to eq("Standup")
    end

    it "blocks deleting a recurring event" do
      expect { delete calendar_event_path(recurring) }.not_to change(CalendarEvent, :count)
    end
  end

  describe "manual sync now" do
    it "enqueues a poll when connected" do
      expect { post sync_calendar_connection_path }.to have_enqueued_job(CalendarPollJob)
      expect(response).to redirect_to(calendar_connection_path)
    end
  end

  describe "error surfacing" do
    it "shows a localized error detail when the last sync failed" do
      connection.update!(status: "error", last_error_code: "pull")
      get calendar_connection_path
      expect(response.body).to include(I18n.t("calendar_connection.error_detail.pull"))
    end
  end
end
