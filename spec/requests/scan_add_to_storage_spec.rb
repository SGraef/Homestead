# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Scan -> add to storage" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:product)   { create(:product, household: household, name: "Vollmilch", unit: "l", barcode: "4006381333924") }
  let(:fridge)    { household.locations.find_by!(kind: "fridge") }

  before do
    household
    login_via_post(user)
  end

  it "creates a StorageItem for the scanned product and bounces back to the scan page" do
    expect {
      post storage_items_path, params: {
        storage_item: { product_id: product.id, quantity: 2, location_id: fridge.id },
        return_to:    "scan"
      }
    }.to change(StorageItem, :count).by(1)

    expect(response).to redirect_to(scan_products_path)
    follow_redirect!
    expect(flash[:notice]).to include("Vollmilch")
    item = StorageItem.last
    expect(item).to have_attributes(product: product, quantity: 2, location: fridge)
  end

  it "still lands on storage_items index when return_to isn't 'scan'" do
    post storage_items_path, params: {
      storage_item: { product_id: product.id, quantity: 1, location_id: fridge.id }
    }
    expect(response).to redirect_to(storage_items_path)
  end

  it "renders the add-to-storage form on a successful barcode lookup" do
    get lookup_products_path, params: { barcode: product.barcode },
                              headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).to include("return_to")
    expect(response.body).to include(I18n.t("scan.add_to_storage"))
  end
end
