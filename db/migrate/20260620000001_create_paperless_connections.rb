# frozen_string_literal: true

# Per-household binding to a self-hosted paperless-ngx instance. The API token
# is encrypted at rest via Active Record encryption (see PaperlessConnection).
class CreatePaperlessConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :paperless_connections do |t|
      t.references :household, null: false, foreign_key: true, index: { unique: true }
      t.string :base_url, null: false
      # Encrypted ciphertext is much longer than the raw 40-char token, so a
      # plain varchar(255) could overflow -- use text.
      t.text :api_token
      t.boolean :verify_ssl, null: false, default: true
      # Comma-separated tags applied to every document Homestead uploads
      # (e.g. "homestead"), so they're easy to find / train on in paperless.
      t.string :default_tags
      t.datetime :last_synced_at
      t.string :last_error, limit: 1000

      t.timestamps
    end
  end
end
