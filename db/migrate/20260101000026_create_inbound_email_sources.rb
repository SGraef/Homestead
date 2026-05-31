# frozen_string_literal: true

# Per-(user, household) IMAP mailbox config that the inbound-receipts
# poller drains on each tick. Replaces the earlier RECEIPT_IMAP_* env
# vars: every field that used to be process-wide now lives per row,
# the password is encrypted at rest, and a user can have several
# sources (different providers, different folders, different
# households).
class CreateInboundEmailSources < ActiveRecord::Migration[8.0]
  def change
    create_table :inbound_email_sources do |t|
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.references :user,      null: false, foreign_key: { on_delete: :cascade }

      t.string  :label, null: false, limit: 80
      t.string  :imap_host, null: false, limit: 255
      t.integer :imap_port, null: false, default: 993
      t.boolean :imap_ssl,  null: false, default: true
      t.string  :imap_username, null: false, limit: 255
      # Holds the AR-encrypted ciphertext envelope. `text` because
      # the envelope is JSON-wrapped and binary-padded, comfortably
      # longer than the cleartext.
      t.text    :imap_password, null: false

      # Exact IMAP folder path to poll. Servers vary on hierarchy
      # delimiter ("INBOX/Receipts" vs "INBOX.Receipts"); we store
      # whatever the user types and pass it to imap.select verbatim.
      t.string  :folder, null: false, limit: 255, default: "INBOX"

      # Mark-Seen-only (default) vs. expunge processed mail.
      t.boolean :expunge, null: false, default: false

      # Telemetry for the UI.
      t.datetime :last_polled_at
      t.string   :last_error, limit: 1000

      t.timestamps
    end

    # Same (host, username, folder) combination shouldn't be set up
    # twice in one household -- it would just process the same mail
    # repeatedly.
    add_index :inbound_email_sources,
              %i[household_id imap_host imap_username folder],
              unique: true,
              name:   "idx_inbound_email_sources_unique_per_household"
  end
end
