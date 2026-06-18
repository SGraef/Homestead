# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Reminders::ExpiryScanner do
  let(:admin)     { create(:user) }
  let(:member)    { create(:user) }
  let(:household) { create(:household, admin: admin) }

  before do
    create(:membership, user: member, household: household, role: "member")
  end

  def item(name:, expires_on:)
    product = create(:product, household: household, name: name)
    create(:storage_item, household: household, product: product, expires_on: expires_on)
  end

  it "notifies every member about an item expiring within the heads-up window" do
    item(name: "Joghurt", expires_on: Date.current + 2)

    expect { described_class.run(household) }
      .to change { Notification.where(kind: "storage_expiring").count }.by(2)

    recipients = Notification.where(kind: "storage_expiring").pluck(:user_id)
    expect(recipients).to contain_exactly(admin.id, member.id)
    expect(Notification.last.body).to include("Joghurt")
  end

  it "treats an item due today as expiring (inclusive lower bound)" do
    item(name: "Milch", expires_on: Date.current)
    expect { described_class.run(household) }
      .to change { Notification.where(kind: "storage_expiring").count }.by(2)
  end

  it "notifies about an item that expired within the grace window" do
    item(name: "Hack", expires_on: Date.current - 2)

    expect { described_class.run(household) }
      .to change { Notification.where(kind: "storage_expired").count }.by(2)
    expect(Notification.where(kind: "storage_expired").first.notifiable).to be_a(StorageItem)
  end

  it "ignores items far in the future and items expired long ago" do
    item(name: "Konserve", expires_on: Date.current + 30)
    item(name: "Altbrot",  expires_on: Date.current - 30)

    expect { described_class.run(household) }.not_to change(Notification, :count)
  end

  it "is idempotent: a second run on the same day creates nothing new" do
    item(name: "Butter", expires_on: Date.current + 1)

    described_class.run(household)
    expect { described_class.run(household) }.not_to change(Notification, :count)
  end

  it "re-notifies when an item's expiry date changes" do
    storage = item(name: "Käse", expires_on: Date.current + 1)
    described_class.run(household)

    storage.update!(expires_on: Date.current + 3)
    expect { described_class.run(household) }
      .to change { Notification.where(kind: "storage_expiring").count }.by(2)
  end

  it "links each notification to the storage item it warns about" do
    storage = item(name: "Eier", expires_on: Date.current + 1)
    described_class.run(household)

    notification = Notification.where(kind: "storage_expiring").first
    expect(notification.notifiable).to eq(storage)
    expect(notification.url).to eq("/storage_items/#{storage.id}")
  end

  it "returns the number of notifications created and is a no-op without a household" do
    item(name: "Saft", expires_on: Date.current + 1)
    expect(described_class.run(household)).to eq(2)
    expect(described_class.run(nil)).to eq(0)
  end
end
