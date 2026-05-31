# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "POST /storage_items/:id/move" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:product)   { create(:product, household: household, name: "Apples") }
  let(:pantry)    { household.locations.find_by!(kind: "pantry") }
  let(:fridge)    { household.locations.find_by!(kind: "fridge") }

  before { login_via_post(user) }

  it "moves the requested quantity to a new location" do
    item = create(:storage_item, household: household, product: product,
                                  location: pantry, quantity: 5)

    post move_storage_item_path(item),
         params: { to_location_id: fridge.id, quantity: "2" }

    expect(item.reload.quantity).to eq(3)
    new_row = household.storage_items.find_by(location_id: fridge.id, product: product)
    expect(new_row.quantity).to eq(2)
  end

  it "merges into an existing row at the target (sums quantities)" do
    create(:storage_item, household: household, product: product,
                          location: fridge, quantity: 1)
    item = create(:storage_item, household: household, product: product,
                                  location: pantry, quantity: 4)

    post move_storage_item_path(item),
         params: { to_location_id: fridge.id, quantity: "3" }

    fridge_row = household.storage_items.find_by(location_id: fridge.id, product: product)
    expect(fridge_row.quantity).to eq(4) # 1 + 3
    expect(item.reload.quantity).to eq(1)
  end

  it "destroys the source row when all units are moved" do
    item = create(:storage_item, household: household, product: product,
                                  location: pantry, quantity: 2)

    expect do
      post move_storage_item_path(item),
           params: { to_location_id: fridge.id, quantity: "2" }
    end.to change { household.storage_items.where(location_id: pantry.id).count }.by(-1)
  end

  it "rejects moving more than is available" do
    item = create(:storage_item, household: household, product: product,
                                  location: pantry, quantity: 1)

    post move_storage_item_path(item),
         params: { to_location_id: fridge.id, quantity: "5" }

    expect(item.reload.quantity).to eq(1)
    expect(flash[:alert]).to be_present
  end
end
