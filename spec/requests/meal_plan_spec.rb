# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Meal plan" do
  let(:user) { create(:user) }
  let!(:household) { create(:household, admin: user) }
  let!(:recipe) { Recipe.create!(household: household, name: "Pancakes", servings: 2) }

  before { login_via_post(user) }

  describe "GET /meal_plan" do
    it "renders the current week's grid by default" do
      get meal_plan_path
      expect(response).to have_http_status(:ok)
      # Monday header day-name should appear; locale-format short
      monday = Date.current.beginning_of_week(:monday)
      expect(response.body).to include(I18n.l(monday, format: "%d.%m."))
    end

    it "honours ?date= to show a specific week" do
      get meal_plan_path(date: "2026-06-15")
      # 2026-06-15 is a Monday, so the grid covers 2026-06-15 .. 2026-06-21.
      expect(response.body).to include("15.06.")
      expect(response.body).to include("21.06.")
    end

    it "ignores garbage ?date= values" do
      get meal_plan_path(date: "not-a-date")
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /meal_plan_entries" do
    it "schedules a recipe at the chosen (date, slot)" do
      expect do
        post meal_plan_entries_path, params: {
          meal_plan_entry: {
            recipe_id: recipe.id, planned_on: "2026-06-15", slot: "dinner", servings: 3
          }
        }
      end.to change(MealPlanEntry, :count).by(1)

      entry = MealPlanEntry.last
      expect(entry).to have_attributes(recipe: recipe, planned_on: Date.new(2026, 6, 15),
                                       slot: "dinner", servings: 3)
      expect(response).to redirect_to(meal_plan_path(date: "2026-06-15"))
    end

    it "rejects unknown slots" do
      expect do
        post meal_plan_entries_path, params: {
          meal_plan_entry: {
            recipe_id: recipe.id, planned_on: "2026-06-15", slot: "brunch"
          }
        }
      end.not_to change(MealPlanEntry, :count)
    end
  end

  describe "DELETE /meal_plan_entries/:id" do
    it "removes the entry" do
      entry = household.meal_plan_entries.create!(
        recipe: recipe, planned_on: Date.current, slot: "lunch"
      )
      expect do
        delete meal_plan_entry_path(entry)
      end.to change(MealPlanEntry, :count).by(-1)
    end
  end
end
