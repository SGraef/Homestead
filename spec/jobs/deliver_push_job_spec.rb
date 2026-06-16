# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe DeliverPushJob do
  let(:household)    { create(:household) }
  let(:user)         { create(:user) }
  let(:notification) { create(:notification, household: household, user: user, title: "Hi", body: "there", url: "/todos/1") }
  let!(:subscription) do
    PushSubscription.create!(user: user, household: household,
                             endpoint: "https://push.example/ep", p256dh: "pub", auth: "secret")
  end

  it "sends a push to each subscription and stamps last_used_at" do
    allow(WebPush).to receive(:payload_send)
    expect { described_class.new.perform(notification.id) }
      .to change { subscription.reload.last_used_at }.from(nil)
    expect(WebPush).to have_received(:payload_send).with(hash_including(endpoint: subscription.endpoint))
  end

  it "prunes a dead subscription on 410/404" do
    allow(WebPush).to receive(:payload_send)
      .and_raise(WebPush::ExpiredSubscription.new(double("resp", body: ""), "push.example"))
    expect { described_class.new.perform(notification.id) }
      .to change(PushSubscription, :count).by(-1)
  end

  it "no-ops when VAPID keys are not configured" do
    allow(Rails.application.config.x).to receive(:vapid).and_return({ public_key: nil, private_key: nil })
    expect(WebPush).not_to receive(:payload_send)
    described_class.new.perform(notification.id)
  end
end
