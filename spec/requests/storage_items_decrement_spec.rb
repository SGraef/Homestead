# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "POST /storage_items/:id/decrement" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:product)   { create(:product, household: household, name: "Milk", unit: "l") }

  before { login_via_post(user) }

  it "subtracts one from the quantity" do
    item = create(:storage_item, household: household, product: product, quantity: 3)

    expect do
      post decrement_storage_item_path(item)
    end.to change { item.reload.quantity }.from(3).to(2)
    expect(response).to redirect_to(storage_items_path)
  end

  it "destroys the row when the result reaches zero" do
    item = create(:storage_item, household: household, product: product, quantity: 1)

    expect do
      post decrement_storage_item_path(item)
    end.to change(StorageItem, :count).by(-1)
  end

  it "preserves the active location filter on redirect" do
    fridge = household.locations.find_by!(kind: "fridge")
    item = create(:storage_item, household: household, product: product, quantity: 2,
                                  location: fridge)
    post decrement_storage_item_path(item, location_id: fridge.id)
    expect(response).to redirect_to(storage_items_path(location_id: fridge.id))
  end
end
