# frozen_string_literal: true
# typed: ignore

# A todo can carry a due date, projected read-only onto the calendar grid.
class AddDueOnToTodos < ActiveRecord::Migration[8.0]
  def change
    add_column :todos, :due_on, :date
    add_index  :todos, %i[household_id due_on]
  end
end
