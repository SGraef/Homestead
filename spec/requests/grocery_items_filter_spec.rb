# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Grocery list filter + purge" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:milk)      { create(:product, household: household, name: "Milk") }
  let(:bread)     { create(:product, household: household, name: "Bread") }

  before do
    create(:grocery_item, household: household, product: milk,  status: "needed")
    create(:grocery_item, household: household, product: bread, status: "purchased")
    login_via_post(user)
  end

  describe "GET /grocery_items" do
    it "hides purchased rows by default" do
      get "/grocery_items"
      expect(response.body).to include("Milk")
      expect(response.body).not_to include(">Bread<")
    end

    it "shows everything when ?show_purchased=1" do
      get "/grocery_items", params: { show_purchased: 1 }
      expect(response.body).to include("Milk", "Bread")
    end
  end

  describe "DELETE /grocery_items/purge_purchased" do
    it "destroys every purchased row and leaves needed rows alone" do
      purchased = -> { household.grocery_items.where(status: "purchased").count }
      needed    = -> { household.grocery_items.where(status: "needed").count }
      expect do
        delete "/grocery_items/purge_purchased"
      end.to change(&purchased).from(1).to(0)
                               .and change(&needed).by(0)

      expect(response).to redirect_to(grocery_items_path)
      follow_redirect!
      expect(response.body).to include("Milk")
    end
  end
end
