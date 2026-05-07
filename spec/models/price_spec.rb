# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Price do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:product)   { create(:product, household: household) }
  let(:store)     { create(:store, household: household) }

  it "rejects a store from another household" do
    other_store = create(:store, household: create(:household, admin: user))
    price = build(:price, product: product, store: other_store)
    expect(price).not_to be_valid
    expect(price.errors[:store]).to be_present
  end

  it "round-trips amount through cents" do
    price = create(:price, product: product, store: store)
    price.amount = "3.49"
    price.save!
    expect(price.amount_cents).to eq(349)
    expect(price.amount).to eq(BigDecimal("3.49"))
  end
end
