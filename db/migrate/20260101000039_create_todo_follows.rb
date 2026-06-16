# frozen_string_literal: true
# typed: ignore

# A member follows a todo to be notified of changes. Assignment auto-follows;
# following on comment is opt-in.
class CreateTodoFollows < ActiveRecord::Migration[8.0]
  def change
    create_table :todo_follows do |t|
      t.references :household, null: false, foreign_key: true
      t.references :todo, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :todo_follows, %i[todo_id user_id], unique: true
  end
end
