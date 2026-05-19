# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Offer watchlist" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  before do
    household
    login_via_post(user)
  end

  describe "POST /offers/watchlist" do
    it "creates a watchlist entry" do
      expect {
        post offer_watchlist_entries_path, params: { entry: { pattern: "Vollmilch" } }
      }.to change(OfferWatchlistEntry, :count).by(1)
      expect(response).to redirect_to(offers_path)
    end

    it "rejects a blank pattern" do
      expect {
        post offer_watchlist_entries_path, params: { entry: { pattern: "  " } }
      }.not_to change(OfferWatchlistEntry, :count)
      expect(flash[:alert]).to be_present
    end

    it "ignores a duplicate (same pattern in same household)" do
      household.offer_watchlist_entries.create!(pattern: "Kaffee")
      expect {
        post offer_watchlist_entries_path, params: { entry: { pattern: "kaffee" } }
      }.not_to change(OfferWatchlistEntry, :count)
    end
  end

  describe "DELETE /offers/watchlist/:id" do
    it "removes a watchlist entry" do
      entry = household.offer_watchlist_entries.create!(pattern: "Tofu")
      expect { delete offer_watchlist_entry_path(entry) }
        .to change(OfferWatchlistEntry, :count).by(-1)
    end
  end

  describe "GET /offers (sort + highlight)" do
    it "sorts offers matching a watchlist pattern above unmatched ones" do
      # 3 offers: one cheap unmatched, one expensive matched, one cheap matched.
      # Default ordering would be cheap-unmatched-first; watchlist sort
      # should pull both "Milch" cards above.
      create(:offer, household: household, external_id: "u1", title: "Brot 1kg",
                     price_cents: 99, valid_until: Date.current + 4)
      create(:offer, household: household, external_id: "m1", title: "Bio Vollmilch 1L",
                     price_cents: 199, valid_until: Date.current + 4)
      create(:offer, household: household, external_id: "m2", title: "Frische Milch 1L",
                     price_cents: 89,  valid_until: Date.current + 4)
      household.offer_watchlist_entries.create!(pattern: "milch")

      get offers_path
      body = response.body
      # Order check via positions of external_ids in the rendered HTML.
      m2 = body.index("Frische Milch 1L")
      m1 = body.index("Bio Vollmilch 1L")
      u1 = body.index("Brot 1kg")
      expect([m1, m2].max).to be < u1
      # Highlighted via the watched modifier class.
      expect(body).to include("offer-card--watched")
    end

    it "doesn't add the watched modifier when nothing matches" do
      create(:offer, household: household, external_id: "x", title: "Saft",
                     valid_until: Date.current + 2)
      household.offer_watchlist_entries.create!(pattern: "milch")
      get offers_path
      expect(response.body).not_to include("offer-card--watched")
    end
  end
end
