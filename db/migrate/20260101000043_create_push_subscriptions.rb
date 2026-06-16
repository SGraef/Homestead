# frozen_string_literal: true
# typed: ignore

# Web Push subscriptions. Per-user (subscriptions are private even though the
# household's data is shared). Deduped on SHA-256 of the endpoint — the raw
# endpoint is too long for a MySQL utf8mb4 unique index (3072-byte prefix),
# mirroring api_tokens/invitations.token_digest.
class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :push_subscriptions do |t|
      t.references :user,      null: false, foreign_key: true
      t.references :household, null: false, foreign_key: true
      t.text     :endpoint,        null: false
      t.string   :endpoint_digest, null: false
      t.string   :p256dh,          null: false
      t.string   :auth,            null: false
      t.string   :user_agent
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :push_subscriptions, :endpoint_digest, unique: true
  end
end
