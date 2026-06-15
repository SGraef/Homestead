# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe BringPullAllJob do
  it "enqueues a BringPullJob only for the single (canonical) household" do
    canonical = create(:household, admin: create(:user)) # oldest -> Household.current
    other     = create(:household, admin: create(:user))

    BringConnection.create!(
      household: canonical, bring_email: "a@example.com", bring_user_uuid: "u-a",
      access_token: "tok", default_list_uuid: "l-a", country_code: "DE"
    )
    # A connection on a non-canonical (orphaned) household must be ignored --
    # single-household instances never sync other households' data.
    BringConnection.create!(
      household: other, bring_email: "b@example.com", bring_user_uuid: "u-b",
      access_token: "tok", default_list_uuid: "l-b", country_code: "DE"
    )

    expect do
      described_class.perform_now
    end.to have_enqueued_job(BringPullJob).with(canonical.id).exactly(1).times
  end

  it "enqueues nothing when the household has no connected Bring account" do
    canonical = create(:household, admin: create(:user))
    # Present but not connected (no access_token / default_list_uuid).
    BringConnection.create!(
      household: canonical, bring_email: "c@example.com", bring_user_uuid: "u-c",
      country_code: "DE"
    )

    expect do
      described_class.perform_now
    end.not_to have_enqueued_job(BringPullJob)
  end
end
