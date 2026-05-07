# frozen_string_literal: true
# typed: ignore

class CreateStores < ActiveRecord::Migration[8.0]
  def change
    create_table :stores do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.string :chain
      t.string :address
      t.string :url
      t.timestamps
    end
    add_index :stores, %i[household_id name], unique: true
  end
end
