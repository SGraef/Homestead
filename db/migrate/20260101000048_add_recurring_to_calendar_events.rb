# frozen_string_literal: true
# typed: ignore

# Recurring events pulled from a remote calendar are read-only in Pantria (v1):
# we display each expanded instance but never author/round-trip recurrence.
class AddRecurringToCalendarEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :calendar_events, :recurring, :boolean, null: false, default: false
  end
end
