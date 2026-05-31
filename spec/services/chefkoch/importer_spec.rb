# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Chefkoch::Importer do
  let(:user)       { create(:user) }
  let!(:household) { create(:household, admin: user) }
  let(:url)        { "https://www.chefkoch.de/rezepte/9876543210/Tolle-Pizza.html" }

  let(:api_payload) do
    {
      "title"            => "Tolle Pizza",
      "subtitle"         => "Klassiker mit Tomate und Mozzarella",
      "servings"         => 2,
      "preparationTime"  => 15,
      "cookingTime"      => 10,
      "instructions"     => "Teig kneten, ruhen lassen, belegen, backen.",
      "ingredientGroups" => [
        {
          "header"      => nil,
          "ingredients" => [
            { "name" => "Öl",       "unit" => "EL",        "amount" => 4.0, "usageInfo" => "" },
            { "name" => "Wasser",   "unit" => "ml",        "amount" => 250.0, "usageInfo" => "lauwarm" },
            { "name" => "Salz",     "unit" => "Prise(n)",  "amount" => 2.0, "usageInfo" => "" }
          ]
        },
        {
          "header"      => "Belag",
          "ingredients" => [
            { "name" => "Mehl", "unit" => "g", "amount" => 500.0, "usageInfo" => "" },
            { "name" => "Mozzarella", "unit" => "Stück", "amount" => 1.0, "usageInfo" => "" }
          ]
        }
      ]
    }
  end

  describe ".call" do
    before do
      stub_request(:get, "https://api.chefkoch.de/v2/recipes/9876543210")
        .to_return(status: 200, body: api_payload.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    it "creates a Recipe with title/servings/timings/notes" do
      result = described_class.call(url: url, household: household)
      recipe = result.recipe

      expect(recipe).to have_attributes(
        name:         "Tolle Pizza",
        description:  "Klassiker mit Tomate und Mozzarella",
        servings:     2,
        prep_minutes: 15,
        cook_minutes: 10
      )
      expect(recipe.notes).to include("Teig kneten")
    end

    it "creates products for ingredients it hasn't seen before" do
      expect do
        described_class.call(url: url, household: household)
      end.to change(Product, :count).by(5)

      # Mehl mapped to canonical kg/g unit, Stück mapped to pcs, EL/Prise(n) -> pcs default
      mehl = household.products.find_by("LOWER(name) = ?", "mehl")
      expect(mehl.unit).to eq("g")
      mozz = household.products.find_by("LOWER(name) = ?", "mozzarella")
      expect(mozz.unit).to eq("pcs")
    end

    it "links recipe_ingredients to existing products when names match" do
      create(:product, household: household, name: "Mehl", unit: "kg")
      result = described_class.call(url: url, household: household)
      # The pre-existing Mehl row is reused (no second Mehl created)
      expect(household.products.where("LOWER(name) = ?", "mehl").count).to eq(1)
      mehl_link = result.recipe.recipe_ingredients.find { |i| i.product.name.casecmp("Mehl").zero? }
      expect(mehl_link.quantity).to eq(500)
    end

    it "preserves Chefkoch's literal unit when it doesn't map cleanly (EL, Prise(n))" do
      result = described_class.call(url: url, household: household)
      oil = result.recipe.recipe_ingredients.find { |i| i.product.name == "Öl" }
      expect(oil.unit).to eq("EL")
      expect(oil.quantity).to eq(4)

      salt = result.recipe.recipe_ingredients.find { |i| i.product.name == "Salz" }
      expect(salt.unit).to eq("Prise(n)")
    end

    it "leaves the row unit blank when the Chefkoch unit matches the product's unit" do
      result = described_class.call(url: url, household: household)
      water = result.recipe.recipe_ingredients.find { |i| i.product.name == "Wasser" }
      expect(water.unit).to be_blank # display falls back to the product's "ml"
      expect(water.product.unit).to eq("ml")
    end

    it "captures the usageInfo into per-ingredient notes" do
      result = described_class.call(url: url, household: household)
      water = result.recipe.recipe_ingredients.find { |i| i.product.name == "Wasser" }
      expect(water.notes).to eq("lauwarm")
    end

    it "imports to-taste ingredients (amount: 0) as quantity 1 instead of failing" do
      to_taste_payload = api_payload.deep_dup
      to_taste_payload["ingredientGroups"].first["ingredients"] << {
        "name" => "Pfeffer", "unit" => "", "amount" => 0, "usageInfo" => "nach Geschmack"
      }
      stub_request(:get, "https://api.chefkoch.de/v2/recipes/9876543210")
        .to_return(status: 200, body: to_taste_payload.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = described_class.call(url: url, household: household)
      pepper = result.recipe.recipe_ingredients.find { |i| i.product.name == "Pfeffer" }
      expect(pepper.quantity).to eq(1)
      expect(pepper.notes).to eq("nach Geschmack")
    end
  end

  describe "URL parsing" do
    it "rejects URLs that don't carry a recipe ID" do
      expect do
        described_class.call(url: "https://www.chefkoch.de/", household: household)
      end.to raise_error(Chefkoch::Importer::ImportError, /chefkoch/i)
    end
  end

  describe "upstream errors" do
    it "surfaces a clean 404 message" do
      stub_request(:get, "https://api.chefkoch.de/v2/recipes/9876543210")
        .to_return(status: 404, body: "{}")
      expect do
        described_class.call(url: url, household: household)
      end.to raise_error(Chefkoch::Importer::ImportError, /404/i)
    end
  end
end
