# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ProductBarcode do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:butter)    { create(:product, household: household, name: "Butter", barcode: nil) }

  it "stores extra barcodes for the same product" do
    butter.product_barcodes.create!(barcode: "4006381333924", brand: "Kerrygold")
    butter.product_barcodes.create!(barcode: "4002359000018", brand: "ALDI")

    expect(butter.reload.all_barcodes).to match_array(%w[4006381333924 4002359000018])
    expect(butter.all_brands).to match_array(%w[Kerrygold ALDI])
  end

  it "rejects duplicates within the same product" do
    butter.product_barcodes.create!(barcode: "4006381333924")
    dup = butter.product_barcodes.build(barcode: "4006381333924")
    expect(dup).not_to be_valid
  end

  it "rejects a barcode already used as the primary barcode of another product" do
    create(:product, household: household, barcode: "4006381333924")
    pb = butter.product_barcodes.build(barcode: "4006381333924")
    expect(pb).not_to be_valid
    expect(pb.errors[:barcode]).to be_present
  end

  it "rejects a barcode already used by another product as an alternate" do
    other = create(:product, household: household, name: "Toast", barcode: nil)
    other.product_barcodes.create!(barcode: "4006381333924")

    pb = butter.product_barcodes.build(barcode: "4006381333924")
    expect(pb).not_to be_valid
    expect(pb.errors[:barcode]).to be_present
  end

  it "strips non-digits from the barcode on save" do
    pb = butter.product_barcodes.create!(barcode: " 40063 81-333924\n", brand: "Kerrygold")
    expect(pb.barcode).to eq("4006381333924")
  end

  describe "Product.by_barcode" do
    let!(:butter_pb) { butter.product_barcodes.create!(barcode: "4006381333924", brand: "Kerrygold") }
    let!(:other)     { create(:product, household: household, name: "Toast", barcode: "1111111111111") }

    it "matches via the alternate barcode" do
      expect(Product.by_barcode("4006381333924")).to contain_exactly(butter)
    end

    it "still matches via the primary barcode" do
      expect(Product.by_barcode("1111111111111")).to contain_exactly(other)
    end

    it "returns an empty relation for an unknown barcode" do
      expect(Product.by_barcode("0000000000000")).to be_empty
    end
  end
end
