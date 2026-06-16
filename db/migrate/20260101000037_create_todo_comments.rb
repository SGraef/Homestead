# frozen_string_literal: true
# typed: ignore

# Comments on a todo. Todo-scoped (no polymorphism — YAGNI). The body is the
# input for the German keyword/date extraction in a later phase.
class CreateTodoComments < ActiveRecord::Migration[8.0]
  def change
    create_table :todo_comments do |t|
      t.references :household, null: false, foreign_key: true
      t.references :todo,      null: false, foreign_key: true
      t.references :user,      null: true, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
  end
end
