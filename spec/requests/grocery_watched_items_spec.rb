# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "GET /grocery_items — watched items from the watchlist" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  before do
    household
    login_via_post(user)
  end

  def make_offer(title:, retailer:, price_cents:, valid_until: Date.current + 7)
    household.offers.create!(
      retailer_name: retailer, source: "marktguru", external_id: "#{retailer}-#{title}",
      title: title, price_cents: price_cents, currency: "EUR",
      valid_from: Date.current, valid_until: valid_until
    )
  end

  it "lists watchlist patterns inline as watched items with a badge" do
    household.offer_watchlist_entries.create!(pattern: "Kaffee")
    get grocery_items_path
    expect(response.body).to include("Kaffee")
    expect(response.body).to include(I18n.t("grocery.watched.badge"))
  end

  it "shows the cheapest current matching offer, ignoring non-matching + expired ones" do
    household.offer_watchlist_entries.create!(pattern: "Kaffee")
    make_offer(title: "Jacobs Kaffee", retailer: "Edeka", price_cents: 599)
    make_offer(title: "Tchibo Kaffee", retailer: "Lidl",  price_cents: 449)
    make_offer(title: "Bio Milch",     retailer: "REWE",  price_cents: 89) # no pattern match
    make_offer(title: "Alter Kaffee",  retailer: "Aldi",  price_cents: 199, valid_until: Date.current - 1)

    get grocery_items_path

    expect(response.body).to include("Lidl").and include("4,49")
    expect(response.body).not_to include("Aldi")
    expect(response.body).not_to include("Edeka")
  end

  it "renders an add-to-list button carrying the pattern" do
    household.offer_watchlist_entries.create!(pattern: "Tonic Water")
    get grocery_items_path
    expect(response.body).to include('name="grocery_item[name]"').and include('value="Tonic Water"')
  end

  it "adds a watched item to the list as a needed grocery item" do
    expect do
      post grocery_items_path, params: { grocery_item: { name: "Tonic Water", quantity: 1 } }
    end.to change(GroceryItem, :count).by(1)
    item = GroceryItem.last
    expect(item.name).to eq("Tonic Water")
    expect(item.status).to eq("needed")
  end

  it "shows no watched rows when the watchlist is empty" do
    get grocery_items_path
    expect(response.body).not_to include(I18n.t("grocery.watched.badge"))
  end
end
