# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe GroceryItem do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:product)   { create(:product, household: household) }
  let(:store)     { create(:store, household: household) }

  describe "#mark_purchased!" do
    it "flips status, records purchase metadata and creates a storage item" do
      item = create(:grocery_item, household: household, product: product, quantity: 2)

      expect {
        item.mark_purchased!(store: store, paid_amount: "1.99", expires_on: Date.current + 7,
                             location: "fridge")
      }.to change(StorageItem, :count).by(1)

      item.reload
      expect(item.status).to eq("purchased")
      expect(item.purchased_at).to be_present
      expect(item.paid_amount_cents).to eq(199)
      expect(item.store).to eq(store)
      expect(StorageItem.last).to have_attributes(
        product: product, household: household, quantity: 2
      )
      # `location` is a Location association, but mark_purchased! accepts the
      # location *kind* string and resolves it -- assert via .kind.
      expect(StorageItem.last.location.kind).to eq("fridge")
    end
  end
end
