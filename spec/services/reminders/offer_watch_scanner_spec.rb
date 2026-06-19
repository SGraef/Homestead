# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Reminders::OfferWatchScanner do
  let(:admin)     { create(:user) }
  let(:member)    { create(:user) }
  let(:household) { create(:household, admin: admin) }

  before do
    create(:membership, user: member, household: household, role: "member")
  end

  def watch(pattern)
    household.offer_watchlist_entries.create!(pattern: pattern)
  end

  it "notifies every member when a current offer matches a watched pattern" do
    watch("vollmilch")
    offer = create(:offer, household: household, title: "Bio Vollmilch 1L", retailer_name: "REWE")

    expect { described_class.run(household) }
      .to change { Notification.where(kind: "offer_match").count }.by(2)

    notification = Notification.where(kind: "offer_match").first
    expect(notification.notifiable).to eq(offer)
    expect(notification.url).to eq("/offers")
    expect(Notification.where(kind: "offer_match").pluck(:user_id)).to contain_exactly(admin.id, member.id)
  end

  it "is a no-op when the household has no watchlist" do
    create(:offer, household: household, title: "Bio Vollmilch 1L")
    expect { described_class.run(household) }.not_to change(Notification, :count)
  end

  it "ignores offers that match nothing on the watchlist" do
    watch("kaffee")
    create(:offer, household: household, title: "Bio Vollmilch 1L")
    expect { described_class.run(household) }.not_to change(Notification, :count)
  end

  it "ignores offers that are no longer current" do
    watch("vollmilch")
    create(:offer, household: household, title: "Bio Vollmilch 1L",
                   valid_from: Date.current - 10, valid_until: Date.current - 1)
    expect { described_class.run(household) }.not_to change(Notification, :count)
  end

  it "is idempotent: re-running does not duplicate alerts for the same offer" do
    watch("vollmilch")
    create(:offer, household: household, title: "Bio Vollmilch 1L")

    described_class.run(household)
    expect { described_class.run(household) }.not_to change(Notification, :count)
  end

  it "skips a member who opted out of offer alerts" do
    member.notification_preference.update!(disabled_kinds: ["offer_match"])
    watch("vollmilch")
    create(:offer, household: household, title: "Bio Vollmilch 1L")

    described_class.run(household)

    expect(Notification.where(kind: "offer_match").pluck(:user_id)).to eq([admin.id])
  end

  it "returns the count created and is a no-op without a household" do
    watch("vollmilch")
    create(:offer, household: household, title: "Bio Vollmilch 1L")
    expect(described_class.run(household)).to eq(2)
    expect(described_class.run(nil)).to eq(0)
  end
end
