# frozen_string_literal: true
# typed: ignore

# Remembers that a member dismissed a detected-date suggestion on a comment, so
# the chip never re-nags. Keyed by comment + a hash of the matched span.
class CreateSuggestionDismissals < ActiveRecord::Migration[8.0]
  def change
    create_table :suggestion_dismissals do |t|
      t.references :todo_comment, null: false, foreign_key: true
      t.string :span_hash, null: false
      t.timestamps
    end

    add_index :suggestion_dismissals, %i[todo_comment_id span_hash], unique: true
  end
end
