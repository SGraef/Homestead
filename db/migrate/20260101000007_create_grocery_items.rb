# frozen_string_literal: true
# typed: ignore

class CreateGroceryItems < ActiveRecord::Migration[8.0]
  def change
    create_table :grocery_items do |t|
      t.references :household, null: false, foreign_key: true
      t.references :product,   null: false, foreign_key: true
      t.references :store,     foreign_key: true
      t.decimal    :quantity,  precision: 12, scale: 3, null: false, default: 1
      t.string     :status,    null: false, default: "needed" # needed / purchased / cancelled
      t.datetime   :purchased_at
      t.decimal    :paid_amount_cents, precision: 12, scale: 0
      t.string     :paid_currency, limit: 3
      t.timestamps
    end
    add_index :grocery_items, %i[household_id status]
  end
end
