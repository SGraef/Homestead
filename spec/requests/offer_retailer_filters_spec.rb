# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "PUT /offers/retailers/bulk" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  before do
    household
    login_via_post(user)
  end

  it "creates rows for newly-ticked retailers and deletes unticked ones" do
    household.offer_retailer_filters.create!(retailer: "Edeka")
    household.offer_retailer_filters.create!(retailer: "Penny")

    put bulk_offer_retailer_filters_path, params: { retailers: %w[Edeka REWE] }

    expect(response).to redirect_to(offers_path)
    expect(household.offer_retailer_filters.pluck(:retailer).sort).to eq(%w[Edeka REWE])
  end

  it "clears the allow-list when nothing is ticked" do
    household.offer_retailer_filters.create!(retailer: "Edeka")

    put bulk_offer_retailer_filters_path, params: { retailers: [""] }

    expect(household.offer_retailer_filters.count).to eq(0)
  end

  it "ignores blank and duplicate values" do
    put bulk_offer_retailer_filters_path,
        params: { retailers: ["REWE", "", "REWE", " Lidl ", "Lidl"] }

    expect(household.offer_retailer_filters.pluck(:retailer).sort).to eq(%w[Lidl REWE])
  end

  it "prunes stored offers outside the new allow-list" do
    create(:product, household: household)
    rewe_offer = household.offers.create!(
      retailer_name: "REWE", source: "marktguru", external_id: "1",
      title: "Apfel", price_cents: 100, currency: "EUR",
      valid_from: Date.current, valid_until: Date.current + 7
    )
    edeka_offer = household.offers.create!(
      retailer_name: "Edeka", source: "marktguru", external_id: "2",
      title: "Birne", price_cents: 120, currency: "EUR",
      valid_from: Date.current, valid_until: Date.current + 7
    )

    put bulk_offer_retailer_filters_path, params: { retailers: ["REWE"] }

    expect { rewe_offer.reload }.not_to raise_error
    expect { edeka_offer.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
