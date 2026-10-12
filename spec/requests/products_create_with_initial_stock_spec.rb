# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec.describe "Create product with initial stock" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:fridge)    { household.locations.find_by!(kind: "fridge") }

  before do
    household
    login_via_post(user)
  end

  it "creates the product and a StorageItem, then returns to the scanner with autostart" do
    expect do
      post products_path, params: {
        product:       { name: "Hafermilch", unit: "l", barcode: "4006381333931" },
        initial_stock: { quantity: "1,5", location_id: fridge.id, expires_on: "2026-12-01" },
        return_to:     "scan"
      }
    end.to change(Product, :count).by(1).and change(StorageItem, :count).by(1)

    expect(response).to redirect_to(scan_products_path(autostart: 1))
    item = StorageItem.last
    expect(item).to have_attributes(product: Product.last, quantity: 1.5, location: fridge,
                                    expires_on: Date.new(2026, 12, 1))
    follow_redirect!
    expect(flash[:notice]).to include("Hafermilch")
  end

  it "only creates the product when no quantity is given" do
    expect do
      post products_path, params: {
        product:       { name: "Senf", unit: "pcs" },
        initial_stock: { quantity: "", location_id: fridge.id }
      }
    end.to change(Product, :count).by(1).and not_change(StorageItem, :count)

    expect(response).to redirect_to(product_path(Product.last))
  end

  it "rolls the product back when the stock quantity is invalid" do
    expect do
      post products_path, params: {
        product:       { name: "Senf", unit: "pcs" },
        initial_stock: { quantity: "0", location_id: fridge.id },
        return_to:     "scan"
      }
    end.to not_change(Product, :count).and not_change(StorageItem, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("initial_stock[quantity]")
    expect(response.body).to include('name="return_to"')
    expect(response.body).to include(CGI.escapeHTML(StorageItem.human_attribute_name(:quantity)))
  end

  it "prefills quantity 1 and keeps return_to when opened from the scanner" do
    get new_product_path(barcode: "4006381333931", return_to: "scan")
    expect(response.body).to include('name="initial_stock[quantity]"')
    expect(response.body).to match(/name="initial_stock\[quantity\]"[^>]*value="1"/)
    expect(response.body).to include(CGI.escapeHTML(I18n.t("product.save_and_scan_next")))
  end

  it "links the unknown-barcode card to the new-product form with return_to=scan" do
    allow(BarcodeLookup).to receive(:call).and_return(nil)
    get lookup_products_path, params:  { barcode: "4006381333948" },
                              headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).to include("return_to=scan")
  end
end
