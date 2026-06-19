# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe NotificationPreference do
  let(:user) { create(:user) }

  describe "#allows?" do
    it "allows every kind by default" do
      pref = described_class.new(user: user)
      expect(pref.allows?("storage_expiring")).to be(true)
    end

    it "denies a kind the user opted out of, leaving others allowed" do
      pref = described_class.new(user: user, disabled_kinds: ["storage_expiring"])
      expect(pref.allows?("storage_expiring")).to be(false)
      expect(pref.allows?("storage_expired")).to be(true)
    end
  end

  describe "#quiet_at?" do
    it "is false when quiet hours are unset" do
      expect(described_class.new(user: user).quiet_at?(3)).to be(false)
    end

    it "covers a same-day window (end exclusive)" do
      pref = described_class.new(user: user, quiet_hours_start: 9, quiet_hours_end: 17)
      expect([pref.quiet_at?(8), pref.quiet_at?(9), pref.quiet_at?(16), pref.quiet_at?(17)])
        .to eq([false, true, true, false])
    end

    it "covers a window that wraps past midnight" do
      pref = described_class.new(user: user, quiet_hours_start: 22, quiet_hours_end: 7)
      expect([pref.quiet_at?(23), pref.quiet_at?(3), pref.quiet_at?(7), pref.quiet_at?(12)])
        .to eq([true, true, false, false])
    end
  end

  it "rejects an out-of-range hour" do
    expect(described_class.new(user: user, quiet_hours_start: 24)).not_to be_valid
  end

  describe "User#notification_preference" do
    it "returns a usable default when none is saved yet" do
      expect(user.notification_preference).to be_a(described_class)
      expect(user.notification_preference.allows?("storage_expiring")).to be(true)
    end
  end
end
