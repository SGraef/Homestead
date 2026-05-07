# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "ProductBarcodes" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:butter)    { create(:product, household: household, name: "Butter", barcode: nil) }

  before { login_via_post(user) }

  it "POST adds a brand variant to the product" do
    expect {
      post product_product_barcodes_path(butter),
           params: { product_barcode: { barcode: "4006381333924", brand: "Kerrygold" } }
    }.to change { butter.product_barcodes.count }.from(0).to(1)

    expect(response).to redirect_to(butter)
  end

  it "POST surfaces validation errors when the barcode collides" do
    create(:product, household: household, barcode: "4006381333924")

    post product_product_barcodes_path(butter),
         params: { product_barcode: { barcode: "4006381333924" } }

    expect(response).to redirect_to(butter)
    follow_redirect!
    expect(response.body).to match(/already|vergeben|taken/i)
  end

  it "DELETE removes a brand variant" do
    pb = butter.product_barcodes.create!(barcode: "4006381333924")

    expect {
      delete product_product_barcode_path(butter, pb)
    }.to change { butter.product_barcodes.count }.from(1).to(0)
  end

  it "PATCH updates brand and quantity_text on an existing alternate" do
    pb = butter.product_barcodes.create!(barcode: "4006381333924")

    patch product_product_barcode_path(butter, pb),
          params: { product_barcode: { brand: "Kerrygold", quantity_text: "250 g" } }

    pb.reload
    expect(pb.brand).to eq("Kerrygold")
    expect(pb.quantity_text).to eq("250 g")
    expect(response).to redirect_to(butter)
  end

  describe "POST /products/attach_barcode (scan flow)" do
    it "attaches the scanned barcode to the chosen product and redirects to it" do
      expect {
        post attach_barcode_products_path,
             params: { product_id: butter.id, barcode: "4006381333924" }
      }.to change { butter.product_barcodes.count }.from(0).to(1)

      expect(response).to redirect_to(butter)
    end

    it "redirects back to scan with an alert when the barcode collides" do
      create(:product, household: household, barcode: "4006381333924")

      post attach_barcode_products_path,
           params: { product_id: butter.id, barcode: "4006381333924" }

      expect(response).to redirect_to(scan_products_path)
      expect(flash[:alert]).to be_present
    end
  end
end
