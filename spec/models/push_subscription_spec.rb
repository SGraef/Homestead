# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe PushSubscription do
  let(:household) { create(:household) }
  let(:user)      { create(:user) }

  it "derives the endpoint digest and dedupes on it" do
    sub = described_class.create!(user: user, household: household,
                                  endpoint: "https://push.example/abc", p256dh: "k", auth: "a")
    expect(sub.endpoint_digest).to eq(Digest::SHA256.hexdigest("https://push.example/abc"))

    dup = described_class.new(user: user, household: household,
                              endpoint: "https://push.example/abc", p256dh: "k", auth: "a")
    expect(dup).not_to be_valid
  end

  it "requires endpoint and keys" do
    expect(described_class.new(user: user, household: household)).not_to be_valid
  end
end
