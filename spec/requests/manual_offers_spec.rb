# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Manual offers" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  before do
    household
    login_via_post(user)
  end

  describe "POST /offers/manual" do
    it "creates an Offer with source: manual + a generated UUID external_id" do
      expect do
        post manual_offers_path, params: { offer: {
          title:               "Bio Vollmilch 1L",
          retailer_name:       "Edeka Weserpark",
          price_euros:         "1.19",
          regular_price_euros: "1.49",
          valid_until:         (Date.current + 5).to_s
        } }
      end.to change(Offer, :count).by(1)

      o = Offer.last
      expect(o.source).to eq("manual")
      expect(o.external_id).to match(/\A[0-9a-f-]{36}\z/) # UUID
      expect(o.title).to eq("Bio Vollmilch 1L")
      expect(o.retailer_name).to eq("Edeka Weserpark")
      expect(o.price_cents).to eq(119)
      expect(o.regular_price_cents).to eq(149)
      expect(o.discount_percent).to eq(20) # (149-119)/149 ≈ 20%
      expect(response).to redirect_to(offers_path)
    end

    it "rerenders new with errors when required fields are missing" do
      expect do
        post manual_offers_path, params: { offer: { title: "" } }
      end.not_to change(Offer, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /offers/manual/:id" do
    it "updates a manual offer" do
      offer = create(:offer, household: household, source: "manual",
                              external_id: SecureRandom.uuid,
                              title: "Old", price_cents: 100)

      patch manual_offer_path(offer), params: { offer: {
        title: "New", retailer_name: offer.retailer_name, price_euros: "0.99"
      } }

      expect(offer.reload).to have_attributes(title: "New", price_cents: 99)
      expect(response).to redirect_to(offers_path)
    end

    it "404s when trying to update a synced (non-manual) offer" do
      offer = create(:offer, household: household, source: "marktguru",
                              external_id: "mg-1")

      patch manual_offer_path(offer), params: { offer: { title: "x" } }
      expect(response).to have_http_status(:not_found)
      expect(offer.reload.title).not_to eq("x") # untouched
    end
  end

  describe "DELETE /offers/manual/:id" do
    it "removes a manual offer" do
      offer = create(:offer, household: household, source: "manual",
                              external_id: SecureRandom.uuid)

      expect do
        delete manual_offer_path(offer)
      end.to change(Offer, :count).by(-1)
      expect(response).to redirect_to(offers_path)
    end
  end
end
