# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe BringPullAllJob do
  it "enqueues a per-household BringPullJob for every connected household" do
    user_a = create(:user)
    user_b = create(:user)
    h_a = create(:household, admin: user_a)
    h_b = create(:household, admin: user_b)

    BringConnection.create!(
      household: h_a, bring_email: "a@example.com", bring_user_uuid: "u-a",
      access_token: "tok", default_list_uuid: "l-a", country_code: "DE"
    )
    BringConnection.create!(
      household: h_b, bring_email: "b@example.com", bring_user_uuid: "u-b",
      access_token: "tok", default_list_uuid: "l-b", country_code: "DE"
    )
    # A household without an access_token is skipped.
    h_c = create(:household, admin: create(:user))
    BringConnection.create!(
      household: h_c, bring_email: "c@example.com", bring_user_uuid: "u-c",
      country_code: "DE"
    )

    expect {
      described_class.perform_now
    }.to have_enqueued_job(BringPullJob).exactly(2).times
  end
end
