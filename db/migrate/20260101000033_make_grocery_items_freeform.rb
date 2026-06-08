# frozen_string_literal: true
# typed: false

# Lets a GroceryItem stand on its own with just a free-form `name`
# instead of forcing the user to materialise a full Product every
# time they jot something down on the list. Existing rows keep their
# product_id; new flows (the "type something into the list" form,
# Bring -> Pantria pull) can omit it.
class MakeGroceryItemsFreeform < ActiveRecord::Migration[8.0]
  def up
    add_column :grocery_items, :name, :string, limit: 200
    change_column_null :grocery_items, :product_id, true
  end

  def down
    # Reversible only when no freeform rows exist. Backfilling
    # synthetic products for nameless rows isn't safe.
    raise ActiveRecord::IrreversibleMigration if GroceryItem.exists?(product_id: nil)

    change_column_null :grocery_items, :product_id, false
    remove_column      :grocery_items, :name
  end
end
