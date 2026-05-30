# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "POST /meal_plan/suggest" do
  let(:user)       { create(:user) }
  let!(:household) { create(:household, admin: user) }
  let(:monday)     { Date.new(2026, 6, 1) }

  before { login_via_post(user) }

  it "creates dinner entries and redirects back to the requested week" do
    5.times { |i| household.recipes.create!(name: "Rec #{i}", servings: 2) }

    expect {
      post suggest_meal_plan_path, params: { date: monday.iso8601 }
    }.to change(MealPlanEntry, :count).by(5)

    expect(response).to redirect_to(meal_plan_path(date: monday.iso8601))
  end

  it "flashes an alert when there are no recipes to choose from" do
    post suggest_meal_plan_path, params: { date: monday.iso8601 }
    expect(response).to redirect_to(meal_plan_path(date: monday.iso8601))
    expect(flash[:alert]).to be_present
  end
end
