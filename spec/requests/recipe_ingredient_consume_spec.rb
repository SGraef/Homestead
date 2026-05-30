# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "POST /recipes/:recipe_id/ingredients/:id/consume" do
  let(:user)       { create(:user) }
  let!(:household) { create(:household, admin: user) }
  let(:flour)      { create(:product, household: household, name: "Mehl", unit: "g") }
  let(:oil)        { create(:product, household: household, name: "Öl",  unit: "ml") }
  let(:fridge)     { household.locations.find_by!(kind: "fridge") }
  let(:pantry)     { household.locations.find_by!(kind: "pantry") }

  let(:recipe) { Recipe.create!(household: household, name: "Bread", servings: 1) }

  before { login_via_post(user) }

  it "drains the soonest-to-expire storage row first and merges leftovers" do
    later   = create(:storage_item, household: household, product: flour, location: pantry,
                                    quantity: 800, expires_on: Date.current + 30)
    earlier = create(:storage_item, household: household, product: flour, location: pantry,
                                    quantity: 300, expires_on: Date.current + 5)
    ing = recipe.recipe_ingredients.create!(product: flour, quantity: 500)

    expect { post consume_recipe_ingredient_path(recipe, ing) }
      .to change { household.storage_items.sum(:quantity) }.by(-500)

    expect { earlier.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(later.reload.quantity).to eq(600) # 800 - (500-300)
    expect(flash[:notice]).to include("500", "Mehl")
  end

  it "flashes a 'short by' notice when storage doesn't cover the recipe" do
    create(:storage_item, household: household, product: flour, location: pantry,
                          quantity: 200, expires_on: Date.current + 30)
    ing = recipe.recipe_ingredients.create!(product: flour, quantity: 500)

    post consume_recipe_ingredient_path(recipe, ing)

    expect(household.storage_items.where(product: flour).count).to eq(0)
    # Locale-agnostic: the number we came up short (300) is in the
    # flash regardless of language.
    expect(flash[:notice]).to include("300")
    expect(flash[:notice]).to include("Mehl")
  end

  it "alerts when there's nothing on hand at all" do
    ing = recipe.recipe_ingredients.create!(product: flour, quantity: 500)

    post consume_recipe_ingredient_path(recipe, ing)

    expect(flash[:alert]).to include("Mehl")
  end

  it "refuses with a unit-mismatch alert when the row unit doesn't match the product unit" do
    create(:storage_item, household: household, product: oil, location: pantry, quantity: 750)
    # Recipe says "4 EL", product is stored in ml — no defensible conversion.
    ing = recipe.recipe_ingredients.create!(product: oil, quantity: 4, unit: "EL")

    expect { post consume_recipe_ingredient_path(recipe, ing) }
      .not_to change { household.storage_items.sum(:quantity) }
    expect(flash[:alert]).to include("EL")
    expect(flash[:alert]).to include("ml")
  end

  it "treats a blank row unit as the product's unit" do
    create(:storage_item, household: household, product: oil, location: pantry, quantity: 750)
    ing = recipe.recipe_ingredients.create!(product: oil, quantity: 250)
    # No unit override on the row -> falls back to product's ml -> proceeds.
    post consume_recipe_ingredient_path(recipe, ing)
    expect(household.storage_items.find_by(product: oil).quantity).to eq(500)
  end

  it "treats a matching row unit as a clean pass-through" do
    create(:storage_item, household: household, product: oil, location: pantry, quantity: 750)
    ing = recipe.recipe_ingredients.create!(product: oil, quantity: 100, unit: "ml")
    post consume_recipe_ingredient_path(recipe, ing)
    expect(household.storage_items.find_by(product: oil).quantity).to eq(650)
  end
end
