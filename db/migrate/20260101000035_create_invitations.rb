# frozen_string_literal: true
# typed: ignore

# Admin-issued invitations to join the single household. Self-registration is
# closed after first run, so this is how new members get an account: an admin
# creates an invitation, the invitee follows a tokened link to set their name +
# password, and the account + membership are created on acceptance.
#
# Only the SHA-256 digest of the token is stored (mirrors ApiToken); the
# plaintext is emailed once and never persisted.
class CreateInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :invitations do |t|
      t.references :household, null: false, foreign_key: true
      t.references :invited_by, null: true, foreign_key: { to_table: :users }
      t.string   :email,        null: false
      t.string   :role,         null: false, default: "member"
      t.string   :token_digest, null: false
      t.datetime :expires_at,   null: false
      t.datetime :accepted_at
      t.timestamps
    end

    add_index :invitations, :token_digest, unique: true
    add_index :invitations, %i[household_id email]
  end
end
