# frozen_string_literal: true
# typed: false

# A dismissed date-suggestion on a comment (so the chip doesn't re-nag).
class SuggestionDismissal < ApplicationRecord
  belongs_to :todo_comment

  validates :span_hash, presence: true, uniqueness: { scope: :todo_comment_id }
end
