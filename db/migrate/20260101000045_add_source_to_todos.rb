# frozen_string_literal: true
# typed: ignore

# Provenance for the calendar->todo direction of the keyword loop. A todo
# generated from a calendar event carries source "calendar_extraction" and the
# originating event id; such a todo never spawns an event back (one-hop).
class AddSourceToTodos < ActiveRecord::Migration[8.0]
  def change
    add_column :todos, :source, :string, null: false, default: "manual"
    add_reference :todos, :source_calendar_event, null: true, foreign_key: { to_table: :calendar_events }
  end
end
