# frozen_string_literal: true

# Recipes are per-household so two households on the same instance
# can have their own (overlapping) cookbooks. The cheapest-ingredient
# / availability checks lean on RecipeIngredient -> Product to look
# at the household's storage, so a recipe always lives in exactly
# one household.
class CreateRecipes < ActiveRecord::Migration[8.0]
  def change
    create_table :recipes do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.string  :name,        null: false, limit: 200
      t.text    :description
      t.integer :servings,    null: false, default: 1
      t.integer :prep_minutes
      t.integer :cook_minutes
      t.text    :notes
      t.timestamps
    end

    add_index :recipes, %i[household_id name], name: "idx_recipes_household_name"
  end
end
