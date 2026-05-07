# frozen_string_literal: true
# typed: ignore

class CreateBringConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :bring_connections do |t|
      t.references :household, null: false, foreign_key: true,
                               index: { unique: true }
      t.string  :bring_email,             null: false
      t.string  :bring_user_uuid,         null: false
      t.string  :default_list_uuid
      t.string  :default_list_name
      t.string  :access_token,            limit: 1024
      t.string  :refresh_token,           limit: 1024
      t.datetime :access_token_expires_at
      t.string  :country_code,            limit: 2, default: "DE"
      t.string  :last_error,              limit: 500
      t.datetime :last_synced_at
      t.timestamps
    end
  end
end
