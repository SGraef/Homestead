# frozen_string_literal: true
# typed: ignore

class CreateStorageItems < ActiveRecord::Migration[8.0]
  def change
    create_table :storage_items do |t|
      t.references :household, null: false, foreign_key: true
      t.references :product,   null: false, foreign_key: true
      t.decimal    :quantity,  precision: 12, scale: 3, null: false, default: 1
      t.string     :location,  default: "pantry" # pantry / fridge / freezer / cellar
      t.date       :expires_on
      t.date       :opened_on
      t.timestamps
    end
    add_index :storage_items, %i[household_id product_id location]
    add_index :storage_items, :expires_on
  end
end
