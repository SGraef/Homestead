# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Notification do
  let(:household) { create(:household) }
  let(:user)      { create(:user) }

  describe ".deliver" do
    let(:attrs) { { household: household, user: user, kind: "assigned", title: "Hi" } }

    it "creates a notification" do
      expect { described_class.deliver(dedup_key: "k1", **attrs) }
        .to change(described_class, :count).by(1)
    end

    it "is idempotent on dedup_key (same event twice -> one row)" do
      described_class.deliver(dedup_key: "k1", **attrs)
      expect { described_class.deliver(dedup_key: "k1", **attrs) }
        .not_to change(described_class, :count)
    end
  end

  describe "#mark_read!" do
    it "sets read_at once" do
      n = create(:notification, household: household, user: user)
      expect { n.mark_read! }.to change(n, :read?).from(false).to(true)
      first = n.read_at
      n.mark_read!
      expect(n.read_at).to eq(first)
    end
  end

  it "scopes unread" do
    create(:notification, household: household, user: user)
    create(:notification, household: household, user: user, read_at: Time.current)
    expect(described_class.unread.count).to eq(1)
  end
end
