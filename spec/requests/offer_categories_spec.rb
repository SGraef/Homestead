# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Offer-category management" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }  # auto-seeds defaults

  before do
    household
    login_via_post(user)
  end

  describe "GET /offers/categories" do
    it "renders the household's categories + keywords" do
      get offer_categories_path
      expect(response).to have_http_status(:ok)
      # Seeded categories from the YAML show up.
      expect(response.body).to include("Süßigkeiten")
      expect(response.body).to include("Fleisch &amp; Wurst").or include("Fleisch & Wurst")
      expect(response.body).to include("milka").or include("hähnchen")
    end
  end

  describe "POST /offers/categories" do
    it "creates a category" do
      expect {
        post offer_categories_path, params: {
          offer_category: { name: "Custom Bucket", position: 5 }
        }
      }.to change(household.offer_categories, :count).by(1)
      expect(response).to redirect_to(offer_categories_path)
    end

    it "rejects a duplicate name (case-insensitive)" do
      household.offer_categories.create!(name: "Käse", position: 999)
      expect {
        post offer_categories_path, params: {
          offer_category: { name: "KÄSE", position: 1000 }
        }
      }.not_to change(OfferCategory, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /offers/categories/:id" do
    it "renames + repositions a category" do
      cat = household.offer_categories.create!(name: "Old", position: 100)
      patch offer_category_path(cat), params: {
        offer_category: { name: "New", position: 5 }
      }
      cat.reload
      expect(cat.name).to eq("New")
      expect(cat.position).to eq(5)
    end
  end

  describe "DELETE /offers/categories/:id" do
    it "removes a category and cascades its keywords" do
      cat = household.offer_categories.create!(name: "Goner", position: 999)
      cat.offer_category_keywords.create!(keyword: "doomed")

      expect { delete offer_category_path(cat) }
        .to change(OfferCategory, :count).by(-1)
         .and change(OfferCategoryKeyword, :count).by(-1)
    end
  end

  describe "POST /offers/categories/reset_defaults" do
    it "wipes and re-seeds from the YAML" do
      household.offer_categories.destroy_all
      household.offer_categories.create!(name: "Custom Only", position: 1)

      post reset_defaults_offer_categories_path
      names = household.offer_categories.reload.pluck(:name)
      expect(names).not_to include("Custom Only")
      expect(names).to include("Süßigkeiten", "Fleisch & Wurst")
    end
  end

  describe "POST /offers/categories/:id/keywords" do
    it "adds a keyword (downcased + trimmed)" do
      cat = household.offer_categories.first
      expect {
        post offer_category_offer_category_keywords_path(cat),
             params: { offer_category_keyword: { keyword: "  KATZE  " } }
      }.to change(cat.offer_category_keywords, :count).by(1)
      expect(cat.offer_category_keywords.find_by(keyword: "katze")).to be_present
    end

    it "rejects a duplicate keyword in the same category" do
      cat = household.offer_categories.first
      cat.offer_category_keywords.create!(keyword: "dup")

      expect {
        post offer_category_offer_category_keywords_path(cat),
             params: { offer_category_keyword: { keyword: "DUP" } }
      }.not_to change(cat.offer_category_keywords, :count)
    end
  end

  describe "DELETE /offers/categories/:id/keywords/:keyword_id" do
    it "removes a keyword" do
      cat = household.offer_categories.first
      kw  = cat.offer_category_keywords.create!(keyword: "toremove")

      expect {
        delete offer_category_offer_category_keyword_path(cat, kw)
      }.to change(cat.offer_category_keywords, :count).by(-1)
    end
  end
end
