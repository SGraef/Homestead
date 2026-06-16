# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Push subscriptions" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin) }
  let(:json)       { { "CONTENT_TYPE" => "application/json" } }
  let(:payload)    { { endpoint: "https://push.example/xyz", keys: { p256dh: "pub", auth: "secret" } } }

  before { login_via_post(admin) }

  it "creates a subscription owned by the current user" do
    expect { post push_subscriptions_path, params: payload.to_json, headers: json }
      .to change(PushSubscription, :count).by(1)
    expect(response).to have_http_status(:created)
    expect(PushSubscription.last.user).to eq(admin)
  end

  it "upserts on the same endpoint (no duplicate)" do
    post push_subscriptions_path, params: payload.to_json, headers: json
    expect { post push_subscriptions_path, params: payload.to_json, headers: json }
      .not_to change(PushSubscription, :count)
  end

  it "rejects a payload missing keys" do
    post push_subscriptions_path, params: { endpoint: "https://push.example/x" }.to_json, headers: json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "destroys a subscription by endpoint" do
    post push_subscriptions_path, params: payload.to_json, headers: json
    expect { delete push_subscriptions_path, params: { endpoint: payload[:endpoint] }.to_json, headers: json }
      .to change(PushSubscription, :count).by(-1)
  end

  it "enqueues a push delivery when an assignment notification is created" do
    member = create(:user)
    Membership.create!(user: member, household: household, role: "member")
    todo = create(:todo, household: household, creator: admin)

    expect { patch todo_path(todo), params: { todo: { assignee_id: member.id } } }
      .to have_enqueued_job(DeliverPushJob)
  end
end
