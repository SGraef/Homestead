# frozen_string_literal: true

# One row per (recipe, product) entry. `unit` is optional -- if blank
# the product's own unit is used at display time. Position drives
# the order ingredients appear in the recipe view (cooks rely on
# order: "first chop the onion, then sauté").
class CreateRecipeIngredients < ActiveRecord::Migration[8.0]
  def change
    create_table :recipe_ingredients do |t|
      t.references :recipe,  null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: { on_delete: :cascade }
      t.decimal :quantity, precision: 12, scale: 3, null: false
      t.string  :unit,     limit: 16
      t.string  :notes,    limit: 200
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :recipe_ingredients, %i[recipe_id position]
  end
end
