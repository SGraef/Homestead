# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Calendar" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin, timezone: "Europe/Berlin") }

  before { login_via_post(admin) }

  describe "GET /calendar (month)" do
    it "renders an event in its correct day cell (household timezone)" do
      # 13:00 UTC on 2026-06-15 is 15:00 Berlin (summer) -> same calendar day.
      create(:calendar_event, household: household, title: "Zahnarzt",
             starts_at: Time.utc(2026, 6, 15, 13, 0))

      get calendar_path(date: "2026-06-15")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-cal-day="2026-06-15"')
      expect(response.body).to include("Zahnarzt")
    end

    it "projects a todo's due date onto the grid (read-only)" do
      create(:todo, household: household, title: "Steuer abgeben", due_on: Date.new(2026, 6, 20))
      get calendar_path(date: "2026-06-15")
      expect(response.body).to include("Steuer abgeben")
    end

    it "buckets a late-evening UTC event on the next Berlin day" do
      # 23:30 UTC on 2026-06-15 is 01:30 Berlin on 2026-06-16.
      create(:calendar_event, household: household, title: "Nachtschicht",
             starts_at: Time.utc(2026, 6, 15, 23, 30))
      get calendar_path(date: "2026-06-16", view: "day")
      expect(response.body).to include('data-cal-day="2026-06-16"')
      expect(response.body).to include("Nachtschicht")
    end
  end

  describe "event CRUD" do
    it "creates an event (parsed in the household timezone, stored UTC)" do
      expect do
        post calendar_events_path, params: {
          calendar_event: { title: "Meeting", starts_at: "2026-06-15T14:00", all_day: "0" }
        }
      end.to change(CalendarEvent, :count).by(1)

      event = CalendarEvent.last
      expect(event.source).to eq("manual")
      # 14:00 Berlin summer = 12:00 UTC.
      expect(event.starts_at.utc.hour).to eq(12)
    end

    it "lets an admin delete an event but denies a non-admin member" do
      event = create(:calendar_event, household: household)
      member = create(:user)
      Membership.create!(user: member, household: household, role: "member")

      login_via_post(member)
      expect { delete calendar_event_path(event) }.not_to change(CalendarEvent, :count)

      login_via_post(admin)
      expect { delete calendar_event_path(event) }.to change(CalendarEvent, :count).by(-1)
    end
  end
end
