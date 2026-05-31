# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Creating products with multiple barcodes" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  before do
    household
    login_via_post(user)
  end

  it "creates the product + nested ProductBarcode rows in one POST" do
    expect do
      post products_path, params: {
        product: {
          name:                        "Butter",
          unit:                        "g",
          barcode:                     "4006381333924",
          brand:                       "Kerrygold",
          product_barcodes_attributes: {
            "0" => { barcode: "4002359000018", brand: "ALDI", quantity_text: "250 g" },
            "1" => { barcode: "4337185040641", brand: "Lurpak" }
          }
        }
      }
    end.to change(Product, :count).by(1)

    product = Product.last
    expect(product.barcode).to eq("4006381333924")
    expect(product.brand).to eq("Kerrygold")
    expect(product.product_barcodes.pluck(:barcode))
      .to match_array(%w[4002359000018 4337185040641])
    expect(response).to redirect_to(product)
  end

  it "rejects rows whose barcode is blank (reject_if on the model)" do
    post products_path, params: {
      product: {
        name: "Butter", unit: "g", barcode: "4006381333924",
        product_barcodes_attributes: {
          "0" => { barcode: "", brand: "Empty" },
          "1" => { barcode: "4002359000018", brand: "ALDI" }
        }
      }
    }

    product = Product.last
    expect(product.product_barcodes.count).to eq(1)
    expect(product.product_barcodes.first.brand).to eq("ALDI")
  end

  it "updates an existing alternate's brand and quantity_text via nested attributes" do
    butter = create(:product, household: household, name: "Butter", barcode: nil)
    pb     = butter.product_barcodes.create!(barcode: "4002359000018", brand: "ALDI")

    patch product_path(butter), params: {
      product: {
        name: "Butter", unit: butter.unit,
        product_barcodes_attributes: {
          "0" => { id: pb.id, barcode: pb.barcode,
                   brand: "ALDI Bio", quantity_text: "250 g" }
        }
      }
    }

    pb.reload
    expect(pb.brand).to eq("ALDI Bio")
    expect(pb.quantity_text).to eq("250 g")
    expect(butter.product_barcodes.count).to eq(1)
  end

  it "destroys an alternate when _destroy=1 is sent on update" do
    butter = create(:product, household: household, name: "Butter", barcode: nil)
    pb     = butter.product_barcodes.create!(barcode: "4002359000018", brand: "ALDI")

    expect do
      patch product_path(butter), params: {
        product: {
          name: "Butter", unit: butter.unit,
          product_barcodes_attributes: {
            "0" => { id: pb.id, _destroy: "1" }
          }
        }
      }
    end.to change { butter.product_barcodes.count }.from(1).to(0)
  end
end
