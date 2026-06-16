# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe CalendarEvent do
  let(:household) { create(:household) }

  it "requires a title, a start, and a valid source" do
    expect(build(:calendar_event, title: nil)).not_to be_valid
    expect(build(:calendar_event, starts_at: nil)).not_to be_valid
    expect(build(:calendar_event, source: "bogus")).not_to be_valid
    expect(build(:calendar_event)).to be_valid
  end

  it "rejects an end before the start" do
    e = build(:calendar_event, starts_at: Time.utc(2026, 6, 15, 12), ends_at: Time.utc(2026, 6, 15, 11))
    expect(e).not_to be_valid
  end

  it "starting_between filters by start time" do
    inside  = create(:calendar_event, household: household, starts_at: Time.utc(2026, 6, 15, 9))
    outside = create(:calendar_event, household: household, starts_at: Time.utc(2026, 7, 1, 9))
    found = household.calendar_events.starting_between(Time.utc(2026, 6, 1), Time.utc(2026, 6, 30))
    expect(found).to include(inside)
    expect(found).not_to include(outside)
  end
end
