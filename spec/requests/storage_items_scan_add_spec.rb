# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "POST /storage_items/scan_add" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:product)   { create(:product, household: household, name: "Mehl", unit: "g", barcode: "4006381333924") }

  before do
    household # touch so the after_create seeds default locations
    login_via_post(user)
  end

  it "creates a storage row in the household's default location for a known barcode" do
    expect do
      post scan_add_storage_items_path,
           params:  { barcode: product.barcode },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end.to change(StorageItem, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with("text/vnd.turbo-stream.html")
    expect(response.body).to include("scan-log")
    expect(response.body).to include("Mehl")

    item = StorageItem.last
    expect(item.product).to eq(product)
    expect(item.quantity).to eq(1)
    expect(item.location).to eq(household.default_storage_location)
  end

  it "honors an explicit location_id" do
    freezer = household.locations.create!(name: "Tiefkühler 2", kind: "freezer")

    post scan_add_storage_items_path,
         params:  { barcode: product.barcode, location_id: freezer.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    item = StorageItem.last
    expect(item.location).to eq(freezer)
    expect(item.frozen_on).to eq(Date.current) # freezer auto-stamps
  end

  it "resolves alternate ProductBarcode rows, not just the primary" do
    product.product_barcodes.create!(barcode: "9999999999999", brand: "Aldi")

    expect do
      post scan_add_storage_items_path,
           params:  { barcode: "9999999999999" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end.to change(StorageItem, :count).by(1)

    expect(StorageItem.last.product).to eq(product)
  end

  it "returns a 422 turbo-stream with a 'create product' deep link when the barcode is unknown" do
    expect do
      post scan_add_storage_items_path,
           params:  { barcode: "0000000000000" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end.not_to change(StorageItem, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("0000000000000")
    expect(response.body).to include(new_product_path(barcode: "0000000000000"))
  end

  it "does not pull a product from a different household" do
    other = create(:household)
    create(:product, household: other, barcode: "5555555555555")

    expect do
      post scan_add_storage_items_path,
           params:  { barcode: "5555555555555" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end.not_to change(StorageItem, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end
end
