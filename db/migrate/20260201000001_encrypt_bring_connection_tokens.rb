# frozen_string_literal: true
# typed: ignore

# Encrypt Bring! OAuth tokens at rest (Active Record encryption). Widen the
# columns for ciphertext overhead, and clear any existing plaintext tokens so an
# encrypted read never hits an unencrypted value — affected households simply
# re-authenticate Bring! on next use (benign; the client already handles a
# blank/expired token by prompting reconnect).
class EncryptBringConnectionTokens < ActiveRecord::Migration[8.0]
  def up
    change_column :bring_connections, :access_token,  :text
    change_column :bring_connections, :refresh_token, :text

    execute(<<~SQL.squish)
      UPDATE bring_connections
      SET access_token = NULL, refresh_token = NULL, access_token_expires_at = NULL
    SQL
  end

  def down
    change_column :bring_connections, :access_token,  :string, limit: 1024
    change_column :bring_connections, :refresh_token, :string, limit: 1024
  end
end
