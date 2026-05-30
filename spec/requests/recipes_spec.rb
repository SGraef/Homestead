# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Recipes" do
  let(:user)      { create(:user) }
  let!(:household) { create(:household, admin: user) }
  let!(:milk)     { create(:product, household: household, name: "Vollmilch", unit: "l") }
  let!(:flour)    { create(:product, household: household, name: "Mehl",       unit: "kg") }

  before { login_via_post(user) }

  describe "CRUD" do
    it "creates a recipe with ingredients" do
      expect {
        post recipes_path, params: {
          recipe: {
            name: "Pancakes", servings: 4, prep_minutes: 10, cook_minutes: 15,
            recipe_ingredients_attributes: {
              "0" => { product_id: milk.id,  quantity: "0.5" },
              "1" => { product_id: flour.id, quantity: "0.3" },
              "2" => { product_id: "",        quantity: "" } # blank row -> reject_if
            }
          }
        }
      }.to change(Recipe, :count).by(1)
       .and change(RecipeIngredient, :count).by(2)

      r = Recipe.last
      expect(r.name).to eq("Pancakes")
      expect(r.recipe_ingredients.pluck(:product_id)).to match_array([milk.id, flour.id])
      expect(response).to redirect_to(r)
    end

    it "shows the index" do
      create(:product) # noise
      Recipe.create!(household: household, name: "Toast", servings: 2)
      get recipes_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Toast")
    end

    it "updates name + servings" do
      r = Recipe.create!(household: household, name: "Pasta", servings: 2)
      patch recipe_path(r), params: { recipe: { name: "Pasta al pesto", servings: 4 } }
      expect(r.reload).to have_attributes(name: "Pasta al pesto", servings: 4)
    end

    it "destroys + cascades the ingredients" do
      r = Recipe.create!(household: household, name: "Soup", servings: 4)
      r.recipe_ingredients.create!(product: milk, quantity: 1)
      expect {
        delete recipe_path(r)
      }.to change(Recipe, :count).by(-1)
       .and change(RecipeIngredient, :count).by(-1)
    end

    it "rejects a product from another household" do
      other_user      = create(:user)
      other_household = create(:household, admin: other_user)
      foreign_product = create(:product, household: other_household)

      r = Recipe.create!(household: household, name: "X", servings: 1)
      ingredient = r.recipe_ingredients.build(product: foreign_product, quantity: 1)
      expect(ingredient).not_to be_valid
      expect(ingredient.errors[:product]).to be_present
    end
  end

  describe "ingredient endpoints" do
    let(:recipe) { Recipe.create!(household: household, name: "Pizza", servings: 2) }

    it "adds an ingredient from the show page" do
      expect {
        post recipe_ingredients_path(recipe),
             params: { recipe_ingredient: { product_id: flour.id, quantity: 0.4 } }
      }.to change(RecipeIngredient, :count).by(1)
      expect(response).to redirect_to(recipe)
    end

    it "removes an ingredient" do
      ing = recipe.recipe_ingredients.create!(product: milk, quantity: 1)
      expect {
        delete recipe_ingredient_path(recipe, ing)
      }.to change(RecipeIngredient, :count).by(-1)
    end
  end
end
