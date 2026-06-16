# frozen_string_literal: true
# typed: false

require "rails_helper"

# The push side is driven by model after_commit hooks, which fire in request
# specs. Verifies the echo guard and provenance gating decide *whether* to push.
RSpec.describe "Calendar two-way push wiring" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin, timezone: "Europe/Berlin") }
  let!(:connection) do
    household.create_calendar_connection!(provider: "google", status: "connected",
                                          access_token: "atk", token_expires_at: 1.hour.from_now, calendar_id: "primary")
  end

  before { login_via_post(admin) }

  it "enqueues a push when an admin creates a local event while connected" do
    expect do
      post calendar_events_path, params: { calendar_event: { title: "Meeting", starts_at: "2026-06-20T14:00" } }
    end.to have_enqueued_job(CalendarPushJob).with("create", hash_including(:event_id))

    expect(CalendarEvent.last.calendar_connection).to eq(connection) # auto-attached
  end

  it "never pushes a remote-origin event, and the echo guard suppresses sync" do
    pulled = connection.calendar_events.create!(household: household, title: "Pulled", sync_origin: "remote",
                                                remote_id: "g1", starts_at: Time.utc(2026, 6, 20, 12))
    expect(pulled.pushable?).to be(false) # remote origin -> never pushed back
    expect(CalendarEvent.without_sync { CalendarEvent.skip_sync? }).to be(true)
    expect(CalendarEvent.skip_sync?).to be(false) # restored after the block
  end

  it "does not push when no calendar is connected" do
    connection.update!(status: "disconnected")
    expect do
      post calendar_events_path, params: { calendar_event: { title: "Solo", starts_at: "2026-06-20T14:00" } }
    end.not_to have_enqueued_job(CalendarPushJob)
  end
end
