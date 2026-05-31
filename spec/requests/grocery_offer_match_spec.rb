# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "GET /grocery_items — offer-match badge" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:milk)      { create(:product, household: household, name: "Vollmilch", unit: "l") }
  let(:apple)     { create(:product, household: household, name: "Apfel",     unit: "kg") }

  before do
    household
    login_via_post(user)
  end

  def make_offer(product:, retailer:, price_cents:, valid_until: Date.current + 7)
    household.offers.create!(
      product: product, retailer_name: retailer, source: "marktguru",
      external_id: "#{retailer}-#{product.id}", title: product.name,
      price_cents: price_cents, currency: "EUR",
      valid_from: Date.current, valid_until: valid_until
    )
  end

  it "renders the offer label next to a needed item that has a current offer" do
    household.grocery_items.create!(product: milk, quantity: 1, status: "needed")
    make_offer(product: milk, retailer: "REWE", price_cents: 99)

    get grocery_items_path

    expect(response.body).to include("0,99") # German number format from locale
    expect(response.body).to include("REWE")
  end

  it "renders no badge when the product has no current offer" do
    household.grocery_items.create!(product: apple, quantity: 1, status: "needed")

    get grocery_items_path

    # The chip is a link.chip.success; the layout has no other instance
    # of that combination, so its absence proves no offer was matched.
    expect(response.body).not_to match(/<a[^>]*class="chip success"[^>]*>/)
  end

  it "picks the cheapest offer across retailers" do
    household.grocery_items.create!(product: milk, quantity: 1, status: "needed")
    make_offer(product: milk, retailer: "REWE",  price_cents: 119)
    make_offer(product: milk, retailer: "Lidl",  price_cents: 89)
    make_offer(product: milk, retailer: "Edeka", price_cents: 129)

    get grocery_items_path

    expect(response.body).to include("Lidl")
    expect(response.body).to include("0,89")
    expect(response.body).not_to include("1,19")
    expect(response.body).not_to include("1,29")
  end

  it "ignores expired offers" do
    household.grocery_items.create!(product: milk, quantity: 1, status: "needed")
    make_offer(product: milk, retailer: "REWE", price_cents: 99,
               valid_until: Date.current - 1)

    get grocery_items_path

    expect(response.body).not_to include("REWE")
  end
end
