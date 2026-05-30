# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe MealPlanSuggester do
  let(:user)       { create(:user) }
  let!(:household) { create(:household, admin: user) }
  let(:monday)     { Date.new(2026, 6, 1) } # Monday

  def recipe(name, tags: nil, servings: 2)
    household.recipes.create!(name: name, servings: servings, tags: tags)
  end

  it "no-ops cleanly when the household has no recipes" do
    result = described_class.new(household: household, week_start: monday).call
    expect(result.scheduled).to eq(0)
    expect(result.reason).to eq(:no_recipes)
  end

  it "fills empty dinner slots with one recipe per day, never repeating within a week" do
    7.times { |i| recipe("Recipe #{i}") }

    expect {
      described_class.new(household: household, week_start: monday).call
    }.to change(MealPlanEntry, :count).by(7)

    week = household.meal_plan_entries.for_week_of(monday)
    expect(week.pluck(:planned_on).sort).to eq((monday..monday + 6.days).to_a)
    expect(week.pluck(:slot).uniq).to eq(["dinner"])
    expect(week.pluck(:recipe_id).uniq.size).to eq(7) # no repeats this week
  end

  it "leaves already-planned dinner slots alone" do
    keep = recipe("Keep me")
    existing = household.meal_plan_entries.create!(
      recipe: keep, planned_on: monday + 2.days, slot: "dinner"
    )
    6.times { |i| recipe("Filler #{i}") }

    described_class.new(household: household, week_start: monday).call

    expect(existing.reload.recipe_id).to eq(keep.id)
    week = household.meal_plan_entries.for_week_of(monday).pluck(:planned_on)
    expect(week.size).to eq(7)
  end

  it "stops without repeating once it runs out of recipes" do
    recipe("Only one")
    result = described_class.new(household: household, week_start: monday).call
    expect(result.scheduled).to eq(1)
    expect(result.skipped_days).to eq(6)
  end

  it "prefers recipes not used in the trailing weeks" do
    fresh   = recipe("Fresh take",       tags: "vegetarisch")
    used    = recipe("Already had this", tags: "vegetarisch")
    # `used` cooked twice in the last 4 weeks; `fresh` never.
    household.meal_plan_entries.create!(recipe: used, planned_on: monday - 10.days, slot: "dinner")
    household.meal_plan_entries.create!(recipe: used, planned_on: monday - 20.days, slot: "dinner")

    result = described_class.new(household: household, week_start: monday).call
    chosen_recipe_ids = result.entries.map(&:recipe_id)
    # `fresh` should be picked at least once; `used` should be picked
    # last (if at all) once the cooldown penalty drops it.
    expect(chosen_recipe_ids.first).to eq(fresh.id)
  end

  it "rewards filling the fish bucket when none has been scheduled yet" do
    fish = recipe("Fischfilet",  tags: "fisch")
    veg  = recipe("Salat",       tags: "vegetarisch")
    meat = recipe("Schweinebraten", tags: "fleisch")

    result = described_class.new(household: household, week_start: monday).call
    chosen_recipe_ids = result.entries.map(&:recipe_id)
    expect(chosen_recipe_ids).to include(fish.id)
    expect(chosen_recipe_ids).to include(veg.id)
  end

  it "doesn't choke when recipes have no tags at all" do
    5.times { |i| recipe("Untagged #{i}") }
    expect {
      described_class.new(household: household, week_start: monday).call
    }.to change(MealPlanEntry, :count).by(5)
  end
end
