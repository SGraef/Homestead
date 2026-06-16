# frozen_string_literal: true
# typed: ignore

# Calendar events for the single household. Times are stored UTC and rendered in
# Household.current.timezone. `source` tracks provenance (manual vs generated
# from a comment/todo) for the keyword loop in a later phase; source_record is
# the originating Comment/Todo and the primary dedup key for generated events.
class CreateCalendarEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :calendar_events do |t|
      t.references :household, null: false, foreign_key: true
      t.string   :title,     null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.boolean  :all_day,   null: false, default: false
      t.string   :source,    null: false, default: "manual"
      t.references :source_record, polymorphic: true, null: true
      t.timestamps
    end

    add_index :calendar_events, %i[household_id starts_at]
  end
end
