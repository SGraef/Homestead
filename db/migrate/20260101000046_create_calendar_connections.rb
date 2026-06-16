# frozen_string_literal: true
# typed: ignore

# The single external-calendar connection for the household (one per instance).
# Google-first: stores the operator's OAuth client + the issued tokens (all
# encrypted via Active Record encryption). Provider is pluggable (CalDAV later).
class CreateCalendarConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :calendar_connections do |t|
      t.references :household, null: false, foreign_key: true, index: { unique: true }
      t.string   :provider, null: false, default: "google"
      t.string   :client_id
      t.text     :client_secret  # encrypted
      t.text     :access_token   # encrypted
      t.text     :refresh_token  # encrypted
      t.datetime :token_expires_at
      t.string   :calendar_id
      t.string   :sync_token, limit: 1024
      t.string   :status, null: false, default: "disconnected"
      t.string   :last_error_code
      t.datetime :last_synced_at
      t.timestamps
    end
  end
end
