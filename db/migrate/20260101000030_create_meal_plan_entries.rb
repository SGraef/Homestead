# frozen_string_literal: true

# Pin a recipe to a (date, slot) on a household's weekly meal plan.
# Multiple entries per slot are allowed -- a "Saturday dinner with
# kids' option" can legitimately be two recipes. The view groups
# by (planned_on, slot) so they render together.
class CreateMealPlanEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :meal_plan_entries do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.references :recipe,    null: false, foreign_key: { on_delete: :cascade }
      t.date    :planned_on, null: false
      # Slot is a free-form short string; the model validates against
      # MealPlanEntry::SLOTS but we keep the column open so a future
      # household-configurable slot list slots in without a migration.
      t.string  :slot,       null: false, limit: 24
      t.decimal :servings,   precision: 8, scale: 2, null: false, default: 1
      t.string  :notes,      limit: 200
      t.timestamps
    end

    add_index :meal_plan_entries, %i[household_id planned_on slot],
              name: "idx_meal_plan_household_date_slot"
  end
end
