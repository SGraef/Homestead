# frozen_string_literal: true
# typed: ignore

# Sync anchors so a CalendarEvent can be reconciled with its remote counterpart.
# sync_origin distinguishes locally-authored events from pulled ones (the
# keyword loop's task_like? gate also requires sync_origin == "local").
class AddSyncAnchorsToCalendarEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :calendar_events, :calendar_connection, null: true, foreign_key: true
    add_column :calendar_events, :remote_id,   :string
    add_column :calendar_events, :etag,        :string
    add_column :calendar_events, :sync_origin, :string, null: false, default: "local"

    # MySQL allows multiple NULLs in a unique index, so local (remote_id IS NULL)
    # rows never collide; remote rows are unique per connection+remote_id.
    add_index :calendar_events, %i[calendar_connection_id remote_id], unique: true,
              name: "index_calendar_events_on_connection_and_remote_id"
  end
end
