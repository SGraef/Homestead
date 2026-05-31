# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Price, "normalized per-unit pricing" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:store)     { create(:store, household: household) }

  def price(unit:, amount_cents:)
    product = create(:product, household: household, unit: unit)
    create(:price, product: product, store: store, amount_cents: amount_cents)
  end

  it "leaves prices priced in their canonical unit unchanged (kg)" do
    p = price(unit: "kg", amount_cents: 199)
    expect(p.amount_per_normalized_unit).to eq(BigDecimal("1.99"))
    expect(p.normalized_unit).to eq("kg")
  end

  it "scales gram-prices into kilogram-prices (×1000)" do
    p = price(unit: "g", amount_cents: 2) # 0.02 €/g
    expect(p.amount_per_normalized_unit).to eq(BigDecimal("20")) # 20.00 €/kg
    expect(p.normalized_unit).to eq("kg")
  end

  it "scales millilitre-prices into litre-prices (×1000)" do
    p = price(unit: "ml", amount_cents: 1) # 0.01 €/ml
    expect(p.amount_per_normalized_unit).to eq(BigDecimal("10")) # 10.00 €/l
    expect(p.normalized_unit).to eq("l")
  end

  it "leaves litre-prices alone" do
    p = price(unit: "l", amount_cents: 119)          # 1.19 €/l
    expect(p.amount_per_normalized_unit).to eq(BigDecimal("1.19"))
    expect(p.normalized_unit).to eq("l")
  end

  it "treats pcs as the canonical 'piece' unit" do
    p = price(unit: "pcs", amount_cents: 50)         # 0.50 €/piece
    expect(p.amount_per_normalized_unit).to eq(BigDecimal("0.5"))
    expect(p.normalized_unit).to eq("piece")
  end

  it "divides by pack_quantity so a 500 g pack reports per-kg" do
    product = create(:product, household: household, unit: "kg")
    p = create(:price, product: product, store: store,
                       amount_cents: 249, pack_quantity: 0.5)
    # €2.49 for 0.5 kg -> €4.98 / kg
    expect(p.amount_per_normalized_unit).to eq(BigDecimal("4.98"))
  end

  it "divides 6-pack pricing into per-piece" do
    product = create(:product, household: household, unit: "pcs")
    p = create(:price, product: product, store: store,
                       amount_cents: 360, pack_quantity: 6)
    # €3.60 for 6 cans -> €0.60 / piece
    expect(p.amount_per_normalized_unit).to eq(BigDecimal("0.6"))
  end

  it "rejects pack_quantity <= 0" do
    product = create(:product, household: household, unit: "kg")
    bad = build(:price, product: product, store: store,
                        amount_cents: 100, pack_quantity: 0)
    expect(bad).not_to be_valid
    expect(bad.errors[:pack_quantity]).to be_present
  end
end
