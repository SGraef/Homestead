# frozen_string_literal: true
# typed: false

class CreateGardenStructures < ActiveRecord::Migration[8.0]
  def change
    create_table :garden_structures do |t|
      t.references :household, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :kind, null: false, default: "other"
      t.json    :boundary, null: false
      t.decimal :height_m, precision: 5, scale: 2, null: false, default: 6.0

      t.timestamps
    end
  end
end
