# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "POST /recipes/:id/shop_missing" do
  let(:user)       { create(:user) }
  let!(:household) { create(:household, admin: user) }
  let(:flour)      { create(:product, household: household, name: "Mehl", unit: "g") }
  let(:milk)       { create(:product, household: household, name: "Vollmilch", unit: "ml") }
  let(:oil)        { create(:product, household: household, name: "Öl", unit: "ml") }
  let(:pantry)     { household.locations.find_by!(kind: "pantry") }
  let(:recipe)     { Recipe.create!(household: household, name: "Pancakes", servings: 2) }

  before { login_via_post(user) }

  it "creates a needed grocery item for the exact deficit when storage is short" do
    recipe.recipe_ingredients.create!(product: flour, quantity: 500)
    create(:storage_item, household: household, product: flour, location: pantry, quantity: 200)

    expect { post shop_missing_recipe_path(recipe) }.to change(GroceryItem, :count).by(1)

    gi = household.grocery_items.find_by(product: flour, status: "needed")
    expect(gi.quantity).to eq(300)
  end

  it "skips ingredients already covered by storage" do
    recipe.recipe_ingredients.create!(product: flour, quantity: 500)
    create(:storage_item, household: household, product: flour, location: pantry, quantity: 800)

    expect { post shop_missing_recipe_path(recipe) }.not_to change(GroceryItem, :count)
  end

  it "bumps an existing 'needed' row instead of duplicating" do
    recipe.recipe_ingredients.create!(product: milk, quantity: 250)
    existing = create(:grocery_item, household: household, product: milk, quantity: 100, status: "needed")

    expect { post shop_missing_recipe_path(recipe) }.not_to change(GroceryItem, :count)
    expect(existing.reload.quantity).to eq(350) # 100 + 250 deficit
  end

  it "doesn't touch already-purchased grocery items (they're history, not pending)" do
    recipe.recipe_ingredients.create!(product: milk, quantity: 250)
    purchased = create(:grocery_item, household: household, product: milk,
                                       quantity: 1, status: "purchased")

    expect { post shop_missing_recipe_path(recipe) }.to change(GroceryItem, :count).by(1)
    expect(purchased.reload.status).to eq("purchased")
    expect(purchased.quantity).to eq(1)
    expect(household.grocery_items.find_by(product: milk, status: "needed").quantity).to eq(250)
  end

  it "skips ingredients whose row-unit doesn't match the product's storage unit" do
    # Recipe says "4 EL" of oil; storage is in ml. No defensible
    # conversion, so we refuse and report it separately.
    recipe.recipe_ingredients.create!(product: oil, quantity: 4, unit: "EL")

    expect { post shop_missing_recipe_path(recipe) }.not_to change(GroceryItem, :count)
    # Flash includes 1 unit-skip count (locale-agnostic check).
    expect(flash[:notice]).to include("1")
  end

  it "summarises the per-row outcome in one flash" do
    # Two missing, one covered, one unit-skipped
    recipe.recipe_ingredients.create!(product: flour, quantity: 500)
    create(:storage_item, household: household, product: flour, location: pantry, quantity: 200)
    recipe.recipe_ingredients.create!(product: milk, quantity: 250)
    recipe.recipe_ingredients.create!(product: oil, quantity: 2, unit: "EL")
    sugar = create(:product, household: household, name: "Zucker", unit: "g")
    recipe.recipe_ingredients.create!(product: sugar, quantity: 100)
    create(:storage_item, household: household, product: sugar, location: pantry, quantity: 500)

    expect { post shop_missing_recipe_path(recipe) }.to change(GroceryItem, :count).by(2)
    expect(response).to redirect_to(recipe)
  end
end
