# frozen_string_literal: true

# Adds bill/receipt classification + due-date tracking to documents. Non-receipt
# documents are OCR'd so a payment due date can be parsed out (see
# ProcessDocumentJob); the extracted text is kept for display / debugging.
class AddDueTrackingToDocuments < ActiveRecord::Migration[8.0]
  def change
    # bill — an invoice/bill that may carry a payment due date
    # receipt — proof of a completed purchase; no due date, no reminder
    # other — contracts, letters, ... treated like a bill for reminders
    add_column :documents, :kind, :string, null: false, default: "bill"
    add_column :documents, :due_on, :date
    # true when due_on came from the document text, false when it's the
    # +1-week fallback applied to a non-receipt with no detectable date.
    add_column :documents, :due_on_detected, :boolean, null: false, default: false
    add_column :documents, :raw_text, :text, size: :medium

    add_index :documents, %i[household_id due_on]
  end
end
