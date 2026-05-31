# frozen_string_literal: true
# typed: false

require "rails_helper"

# Verifies the GroceryItem callbacks enqueue the right Bring sync action,
# and that they no-op cleanly when Bring isn't wired up.
RSpec.describe GroceryItem do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:product)   { create(:product, household: household, name: "Vollmilch") }

  context "without a Bring connection" do
    it "does not enqueue any job on create" do
      expect do
        create(:grocery_item, household: household, product: product, status: "needed")
      end.not_to have_enqueued_job(SyncGroceryToBringJob)
    end
  end

  context "with a Bring connection" do
    before do
      BringConnection.create!(
        household:               household,
        bring_email:             "demo@example.com",
        bring_user_uuid:         "u-1",
        default_list_uuid:       "l-1",
        access_token:            "tok",
        refresh_token:           "r",
        access_token_expires_at: 1.hour.from_now,
        country_code:            "DE"
      )
    end

    it "enqueues a push when a needed item is created" do
      expect do
        create(:grocery_item, household: household, product: product, status: "needed")
      end.to have_enqueued_job(SyncGroceryToBringJob)
        .with(household.id, action: "push", name: "Vollmilch")
    end

    it "enqueues a remove when an item flips from needed to purchased" do
      gi = create(:grocery_item, household: household, product: product, status: "needed")

      expect do
        gi.update!(status: "purchased", purchased_at: Time.current)
      end.to have_enqueued_job(SyncGroceryToBringJob)
        .with(household.id, action: "remove", name: "Vollmilch")
    end

    it "enqueues a remove on destroy" do
      gi = create(:grocery_item, household: household, product: product, status: "needed")

      expect do
        gi.destroy!
      end.to have_enqueued_job(SyncGroceryToBringJob)
        .with(household.id, action: "remove", name: "Vollmilch")
    end
  end
end
