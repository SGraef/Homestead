# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Storage + freezer search" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:milk)      { create(:product, household: household, name: "Vollmilch", brand: "Weihenstephan") }
  let(:apple)     { create(:product, household: household, name: "Apfel") }
  let(:icecream)  { create(:product, household: household, name: "Schoko Eis", brand: "Magnum") }
  let(:fridge)    { household.locations.find_by!(kind: "fridge") }
  let(:freezer)   { household.locations.find_by!(kind: "freezer") }

  before do
    create(:storage_item, household: household, product: milk,     location: fridge)
    create(:storage_item, household: household, product: apple,    location: fridge)
    create(:storage_item, household: household, product: icecream, location: freezer)
    login_via_post(user)
  end

  describe "GET /storage_items?q=" do
    it "filters items by product name substring" do
      get "/storage_items", params: { q: "Voll" }
      expect(response.body).to include("Vollmilch")
      expect(response.body).not_to include(">Apfel<")
    end

    it "matches against brand too" do
      get "/storage_items", params: { q: "magnum" } # collation = ai_ci → case-insensitive
      expect(response.body).to include("Schoko Eis")
      expect(response.body).not_to include(">Vollmilch<")
    end

    it "composes with location filter" do
      get "/storage_items", params: { location_id: fridge.id, q: "Apfel" }
      expect(response.body).to include("Apfel")
      expect(response.body).not_to include(">Vollmilch<")
      expect(response.body).not_to include(">Schoko Eis<")
    end

    it "returns the full list when q is blank" do
      get "/storage_items", params: { q: "" }
      expect(response.body).to include("Vollmilch", "Apfel", "Schoko Eis")
    end
  end

  describe "GET /freezer?q=" do
    it "filters freezer items" do
      get "/freezer", params: { q: "schoko" }
      expect(response.body).to include("Schoko Eis")
    end

    it "drops freezer items that don't match" do
      get "/freezer", params: { q: "vollmilch" }
      expect(response.body).not_to include("Schoko Eis")
    end
  end
end
