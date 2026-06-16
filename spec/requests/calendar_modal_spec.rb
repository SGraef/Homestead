# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Calendar event modal" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin, timezone: "Europe/Berlin") }
  let!(:event)     { create(:calendar_event, household: household, title: "Zahnarzt", starts_at: Time.utc(2026, 6, 15, 12)) }

  before { login_via_post(admin) }

  it "renders event chips that target the modal frame, and the modal dialog" do
    get calendar_path(date: "2026-06-15")
    expect(response.body).to include('data-turbo-frame="modal"')
    expect(response.body).to include('class="modal-dialog"')
  end

  it "renders the edit view inside the modal turbo-frame" do
    get edit_calendar_event_path(event)
    expect(response.body).to include('<turbo-frame id="modal"')
    expect(response.body).to include("Zahnarzt")
  end

  it "does not make recurring events clickable (read-only, no modal link)" do
    rec = household.calendar_events.create!(title: "Standup", recurring: true, sync_origin: "remote",
                                            remote_id: "r9", starts_at: Time.utc(2026, 6, 15, 7))
    get calendar_path(date: "2026-06-15", view: "day")
    expect(response.body).to include("Standup")
    expect(response.body).not_to match(/edit_calendar_event.*#{rec.id}/)
  end
end
