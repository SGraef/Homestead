# frozen_string_literal: true
# typed: ignore

# Collaborative todos for the single household. States are a validated string
# constant (open/in_progress/done) mirroring GroceryItem::STATUSES; assignment
# and follow/notification behaviour land in later phases (assignee_id is carried
# here now but has no side effects until Phase 2).
class CreateTodos < ActiveRecord::Migration[8.0]
  def change
    create_table :todos do |t|
      t.references :household, null: false, foreign_key: true
      t.references :creator,  null: true, foreign_key: { to_table: :users }
      t.references :assignee, null: true, foreign_key: { to_table: :users }
      t.string   :title,       null: false
      t.text     :description
      t.string   :status,      null: false, default: "open"
      t.datetime :completed_at
      t.timestamps
    end

    add_index :todos, %i[household_id status]
  end
end
