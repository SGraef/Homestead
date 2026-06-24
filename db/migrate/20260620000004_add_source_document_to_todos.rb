# frozen_string_literal: true

# Links a payment-reminder todo back to the {Document} (bill) it was generated
# from, mirroring the existing source_calendar_event_id provenance column. The
# FK is nullified (not cascaded) by the Document association so deleting a bill
# leaves any reminder the household already acted on intact.
class AddSourceDocumentToTodos < ActiveRecord::Migration[8.0]
  def change
    add_reference :todos, :source_document, null: true, foreign_key: { to_table: :documents }
  end
end
