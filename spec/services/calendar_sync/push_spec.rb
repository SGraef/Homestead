# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe CalendarSync::Push do
  let(:admin) { create(:user) }
  let(:household) { create(:household, admin: admin, timezone: "Europe/Berlin") }
  let(:connection) do
    create(:calendar_connection, household: household, status: "connected",
           access_token: "atk", token_expires_at: 1.hour.from_now, calendar_id: "primary")
  end
  let(:event) do
    CalendarEvent.create!(household: household, calendar_connection: connection, sync_origin: "local",
                          title: "Zahnarzt", starts_at: Time.utc(2026, 6, 20, 12), ends_at: Time.utc(2026, 6, 20, 13))
  end

  it "creates the remote event and stamps remote_id + etag" do
    stub_request(:post, "https://www.googleapis.com/calendar/v3/calendars/primary/events")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: "g99", etag: '"e99"' }.to_json)

    described_class.new(event).create
    expect(event.reload.remote_id).to eq("g99")
    expect(event.etag).to eq('"e99"')
  end

  it "updates with If-Match and stores the new etag" do
    event.update_columns(remote_id: "g1", etag: '"old"')
    stub = stub_request(:put, "https://www.googleapis.com/calendar/v3/calendars/primary/events/g1")
           .with(headers: { "If-Match" => '"old"' })
           .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                      body: { id: "g1", etag: '"new"' }.to_json)

    described_class.new(event).update
    expect(stub).to have_been_requested
    expect(event.reload.etag).to eq('"new"')
  end

  it "on a 412 conflict keeps the remote version and notifies the admin" do
    event.update_columns(remote_id: "g1", etag: '"stale"')
    stub_request(:put, %r{/calendars/primary/events/g1}).to_return(status: 412, body: "{}")
    stub_request(:get, %r{/calendars/primary/events/g1})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: "g1", etag: '"server"', status: "confirmed", summary: "Zahnarzt (server)",
                         start: { dateTime: "2026-06-20T16:00:00+02:00" }, end: { dateTime: "2026-06-20T17:00:00+02:00" } }.to_json)

    expect { described_class.new(event).update }
      .to change { admin.notifications.where(kind: "calendar_conflict").count }.by(1)

    event.reload
    expect(event.title).to eq("Zahnarzt (server)") # remote wins
    expect(event.etag).to eq('"server"')
  end
end
