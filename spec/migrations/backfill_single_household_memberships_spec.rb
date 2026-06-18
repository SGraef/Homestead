# frozen_string_literal: true
# typed: ignore

# References a db/migrate class, which Sorbet ignores; `typed: ignore` keeps srb tc clean.
require "rails_helper"
require Rails.root.join("db/migrate/20260101000034_backfill_single_household_memberships")

RSpec.describe BackfillSingleHouseholdMemberships do
  subject(:migration) { described_class.new.tap { |m| m.verbose = false } }

  let!(:canonical) { create(:household) }      # oldest -> Household.current
  let!(:other)     { create(:household) }

  def membership(user, household)
    Membership.find_by(user: user, household: household)
  end

  it "enrolls every user into the canonical household without deleting anything" do
    admin_elsewhere  = create(:user)
    member_elsewhere = create(:user)
    Membership.create!(user: admin_elsewhere,  household: other, role: "admin")
    Membership.create!(user: member_elsewhere, household: other, role: "member")

    expect { migration.up }.not_to change(Household, :count)

    expect(membership(admin_elsewhere,  canonical).role).to eq("admin")  # admin anywhere -> admin here
    expect(membership(member_elsewhere, canonical).role).to eq("member")
    # Original memberships on the other household are untouched.
    expect(membership(admin_elsewhere, other)).to be_present
  end

  it "never downgrades an existing canonical admin" do
    admin = create(:user)
    Membership.create!(user: admin, household: canonical, role: "admin")

    migration.up

    expect(membership(admin, canonical).role).to eq("admin")
  end

  it "guarantees at least one admin on the canonical household" do
    only_member = create(:user)
    Membership.create!(user: only_member, household: canonical, role: "member")

    migration.up

    expect(Membership.where(household: canonical, role: "admin")).to exist
  end

  it "is idempotent" do
    user = create(:user)
    Membership.create!(user: user, household: other, role: "member")

    migration.up
    expect { migration.up }.not_to raise_error
    expect(Membership.where(user: user, household: canonical).count).to eq(1)
  end

  it "does nothing when there is no household" do
    Household.destroy_all
    expect(Household.count).to eq(0)
    expect { migration.up }.not_to raise_error
  end
end
