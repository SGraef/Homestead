# frozen_string_literal: true

# Per-user notification settings: the opt-in/opt-out + quiet-hours spine for the
# proactive-reminders engine. One row per user (built lazily).
#   * disabled_kinds  — reminder kinds the user has turned off (opt-out; default
#                       is everything on).
#   * quiet_hours_*   — local hour window (0-23) during which push is suppressed
#                       (the in-app bell still records the notification).
class CreateNotificationPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.integer :quiet_hours_start, limit: 1
      t.integer :quiet_hours_end, limit: 1
      t.json :disabled_kinds

      t.timestamps
    end
  end
end
