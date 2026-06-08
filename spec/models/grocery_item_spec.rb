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

      expect do
        item.mark_purchased!(store: store, paid_amount: "1.99", expires_on: Date.current + 7,
                             location: "fridge")
      end.to change(StorageItem, :count).by(1)

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

    it "just flips status for a freeform row -- no StorageItem is created" do
      item = household.grocery_items.create!(name: "Avocados, 2 ripe", quantity: 1)

      expect do
        result = item.mark_purchased!(store: store, paid_amount: "1.99")
        expect(result).to be_nil
      end.not_to change(StorageItem, :count)

      item.reload
      expect(item.status).to eq("purchased")
      expect(item.paid_amount_cents).to eq(199)
    end
  end

  describe "validations" do
    it "requires either a product or a free-form name" do
      item = household.grocery_items.build(quantity: 1)
      expect(item).not_to be_valid
      expect(item.errors[:base]).to be_present
    end

    it "is valid with just a name (no product)" do
      item = household.grocery_items.build(name: "two avocados", quantity: 1)
      expect(item).to be_valid
    end

    it "is valid with just a product (no name)" do
      item = household.grocery_items.build(product: product, quantity: 1)
      expect(item).to be_valid
    end
  end

  describe "#display_name" do
    it "prefers the linked product's name" do
      product.update!(name: "Milk")
      item = household.grocery_items.create!(product: product, name: "Vollmilch", quantity: 1)
      expect(item.display_name).to eq("Milk")
    end

    it "falls back to the freeform name when no product is linked" do
      item = household.grocery_items.create!(name: "Avocados", quantity: 1)
      expect(item.display_name).to eq("Avocados")
    end
  end
end
