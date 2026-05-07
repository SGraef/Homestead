# frozen_string_literal: true
# typed: ignore

class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.references :household, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :brand
      t.string  :barcode, index: true
      t.string  :unit, default: "pcs", null: false # pcs / g / kg / ml / l
      t.string  :category
      t.text    :notes
      t.timestamps
    end
    # MySQL does not support partial indexes; uniqueness with NULLs is fine in MySQL
    # because multiple NULLs are allowed in a UNIQUE index.
    add_index :products, %i[household_id barcode], unique: true,
                                                   name: "idx_products_household_barcode"
  end
end
