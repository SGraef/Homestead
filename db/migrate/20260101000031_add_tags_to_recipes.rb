# frozen_string_literal: true

# Free-form, comma-separated tag list per recipe ("vegetarisch,
# schnell, italienisch", "fisch, lowcarb", …). MealPlanSuggester
# leans on tag buckets to balance the week (≥2 vegetarian dinners,
# ≥1 fish, ≤4 meat), so the column needs to exist even when no
# recipe carries any tags yet -- the suggester just degrades to
# pure-variety mode in that case.
class AddTagsToRecipes < ActiveRecord::Migration[8.0]
  def change
    add_column :recipes, :tags, :string, limit: 500
  end
end
