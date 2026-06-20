# frozen_string_literal: true

# A stored household document (receipt, bill, invoice, contract...). The file
# itself lives in Active Storage; Homestead is the source of truth. When a
# paperless-ngx connection is configured, each document is also pushed there
# and the resulting document id + classifier output are mirrored back here.
class CreateDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :documents do |t|
      t.references :household, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :title, null: false
      t.text :note
      # stored  — local only (no paperless connection, or not pushed yet)
      # pending — queued / mid-flight upload to paperless
      # synced  — paperless consumed it; paperless_document_id is set
      # failed  — upload or consumption failed; see error_message
      t.string :status, null: false, default: "stored"

      # --- mirrored from paperless-ngx --------------------------------------
      t.integer :paperless_document_id
      t.string :paperless_task_uuid
      t.datetime :paperless_synced_at
      t.string :paperless_document_type
      t.string :paperless_correspondent
      t.text :paperless_tags
      # Best-effort match of the paperless classification onto one of the
      # household's own OfferCategory names (via OfferCategorizer). nil when
      # nothing matched.
      t.string :matched_category
      t.string :error_message, limit: 1000

      t.timestamps
    end

    add_index :documents, %i[household_id status]
    add_index :documents, :paperless_document_id
  end
end
