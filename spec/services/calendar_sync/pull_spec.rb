# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe CalendarSync::Pull do
  let(:household) { create(:household, timezone: "Europe/Berlin") }
  let(:connection) do
    create(:calendar_connection, household: household, status: "connected",
           access_token: "atk", token_expires_at: 1.hour.from_now, calendar_id: "primary")
  end

  def stub_events(body, query: {})
    stub_request(:get, %r{www\.googleapis\.com/calendar/v3/calendars/primary/events})
      .with(query: hash_including(query))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: body.to_json)
  end

  it "upserts a timed remote event (sync_origin remote, UTC stored) and stores the syncToken" do
    stub_events({
      items: [{ id: "g1", etag: '"e1"', status: "confirmed", summary: "Zahnarzt",
                start: { dateTime: "2026-06-20T14:00:00+02:00" }, end: { dateTime: "2026-06-20T15:00:00+02:00" } }],
      nextSyncToken: "tok2"
    })

    expect(described_class.new(connection).call).to be(true)

    event = connection.calendar_events.find_by(remote_id: "g1")
    expect(event.title).to eq("Zahnarzt")
    expect(event.sync_origin).to eq("remote")
    expect(event.starts_at.utc.hour).to eq(12) # 14:00 Berlin = 12:00 UTC
    expect(connection.reload.sync_token).to eq("tok2")
  end

  it "maps an all-day event to local midnight without day-shift" do
    stub_events({ items: [{ id: "g2", etag: '"e"', status: "confirmed", summary: "Urlaub",
                            start: { date: "2026-06-20" }, end: { date: "2026-06-21" } }], nextSyncToken: "t" })
    described_class.new(connection).call
    event = connection.calendar_events.find_by(remote_id: "g2")
    expect(event.all_day).to be(true)
    expect(event.starts_at.in_time_zone("Europe/Berlin").to_date).to eq(Date.new(2026, 6, 20))
  end

  it "deletes on a cancelled item" do
    connection.calendar_events.create!(household: household, title: "old", starts_at: Time.utc(2026, 6, 1, 9),
                                       remote_id: "g3", sync_origin: "remote")
    stub_events({ items: [{ id: "g3", status: "cancelled" }], nextSyncToken: "t" })
    expect { described_class.new(connection).call }
      .to change { connection.calendar_events.where(remote_id: "g3").count }.from(1).to(0)
  end

  it "flags recurring instances and they stay non-pushable (read-only)" do
    stub_events({ items: [{ id: "g4", etag: '"e"', status: "confirmed", summary: "Standup",
                            recurringEventId: "master", start: { dateTime: "2026-06-20T09:00:00+02:00" },
                            end: { dateTime: "2026-06-20T09:15:00+02:00" } }], nextSyncToken: "t" })
    described_class.new(connection).call
    event = connection.calendar_events.find_by(remote_id: "g4")
    expect(event.recurring).to be(true)
    expect(event.pushable?).to be(false)
  end

  it "recovers from an expired syncToken (410) with a full re-sync" do
    connection.update!(sync_token: "stale")
    stub_request(:get, %r{/calendars/primary/events}).with(query: hash_including("syncToken" => "stale"))
      .to_return(status: 410, body: "{}")
    stub_request(:get, %r{/calendars/primary/events}).with(query: hash_including("timeMin" => /.+/))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { items: [], nextSyncToken: "fresh" }.to_json)

    expect(described_class.new(connection).call).to be(true)
    expect(connection.reload.sync_token).to eq("fresh")
  end
end
