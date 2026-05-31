# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Freezer page" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  before do
    household
    login_via_post(user)
  end

  describe "GET /freezer" do
    it "lists freezer items and surfaces stale ones with a warning" do
      fresh = create(:product, household: household, name: "Pommes")
      stale = create(:product, household: household, name: "Brokkoli")
      create(:storage_item, household: household, product: fresh,
                            location: "freezer", frozen_on: 10.days.ago.to_date)
      stale_si = create(:storage_item, household: household, product: stale,
                                       location: "freezer",
                                       frozen_on: 100.days.ago.to_date)

      get "/freezer"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pommes", "Brokkoli")
      expect(stale_si.reload.stale_in_freezer?).to be true
    end
  end

  describe "POST /freezer/homemade" do
    it "creates a homemade product + a freezer storage row in one transaction" do
      expect do
        post homemade_freezer_path,
             params: { name: "Bolognese", unit: "portions",
                       quantity: "4", frozen_on: Date.current.to_s }
      end.to change(Product, :count).by(1)
                                    .and change(StorageItem, :count).by(1)

      product = Product.last
      expect(product.name).to eq("Bolognese")
      expect(product.unit).to eq("portions")
      expect(product.category).to eq(FreezerController::HOMEMADE_CATEGORY)

      storage = StorageItem.last
      expect(storage.location.kind).to eq("freezer")
      expect(storage.quantity).to eq(4)
      expect(storage.frozen_on).to eq(Date.current)
    end

    it "rejects an invalid unit" do
      expect do
        post homemade_freezer_path,
             params: { name: "Tomatensoße", unit: "kg", quantity: "1" }
      end.not_to change(StorageItem, :count)

      expect(response).to redirect_to(freezer_path)
      expect(flash[:alert]).to be_present
    end

    it "rejects a blank name" do
      expect do
        post homemade_freezer_path,
             params: { name: " ", unit: "portions", quantity: "1" }
      end.not_to change(Product, :count)

      expect(response).to redirect_to(freezer_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "stale_in_freezer scope" do
    it "uses created_at when frozen_on is missing (back-compat)" do
      product = create(:product, household: household, name: "Spinat")
      old = create(:storage_item, household: household, product: product,
                                  location: "freezer")
      old.update_columns(created_at: 100.days.ago, frozen_on: nil)

      expect(household.stale_freezer_items).to include(old)
    end
  end
end
