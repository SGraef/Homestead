# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "POST /offers/:id/add_to_list" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user, postal_code: "10115") }

  before do
    household # force the let so the user becomes a member before login
    login_via_post(user)
  end

  context "when the offer is already linked to a known product" do
    it "creates a single GroceryItem and does NOT create a new product" do
      product = create(:product, household: household, name: "Milch", unit: "l")
      offer   = create(:offer, household: household, product: product,
                                title: "Bio Vollmilch 1L")

      expect do
        post add_to_list_offer_path(offer)
      end.to change(GroceryItem, :count).by(1)
                                        .and change(Product, :count).by(0)

      expect(GroceryItem.last.product).to eq(product)
      expect(response).to redirect_to(offers_path)
    end
  end

  context "when the offer has no product yet" do
    it "creates a Product, links it back on the offer, and adds it to the list" do
      offer = create(:offer, household: household, title: "Bio Vollmilch 1L",
                              brand: "Alnatura")

      expect do
        post add_to_list_offer_path(offer)
      end.to change(Product, :count).by(1)
                                    .and change(GroceryItem, :count).by(1)

      product = Product.last
      expect(product.name).to eq("Bio Vollmilch 1L")
      expect(product.brand).to eq("Alnatura")
      expect(offer.reload.product).to eq(product)
      expect(GroceryItem.last.product).to eq(product)
    end
  end

  it "bumps the existing 'needed' grocery item instead of stacking duplicates" do
    product  = create(:product, household: household, name: "Milch")
    offer    = create(:offer, household: household, product: product, title: "Vollmilch 1L")
    existing = create(:grocery_item, household: household, product: product,
                                      quantity: 2, status: "needed")

    expect do
      post add_to_list_offer_path(offer)
    end.not_to change(GroceryItem, :count)

    expect(existing.reload.quantity).to eq(3)
  end
end
