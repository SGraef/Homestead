# frozen_string_literal: true
# typed: ignore

class CreateHouseholds < ActiveRecord::Migration[8.0]
  def change
    create_table :households do |t|
      t.string :name, null: false
      t.string :timezone, default: "UTC", null: false
      t.timestamps
    end

    create_table :memberships do |t|
      t.references :user,      null: false, foreign_key: true
      t.references :household, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :memberships, %i[user_id household_id], unique: true
  end
end
