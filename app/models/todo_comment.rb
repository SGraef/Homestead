# frozen_string_literal: true
# typed: false

# A comment on a {Todo}. Its body is later scanned for German dates/keywords to
# suggest calendar events (suggest-then-confirm).
class TodoComment < ApplicationRecord
  belongs_to :household
  belongs_to :todo
  belongs_to :user, optional: true
  has_many :suggestion_dismissals, dependent: :destroy

  validates :body, presence: true

  before_validation :inherit_household, on: :create

  # Live updates: append/remove the comment on every client viewing this todo
  # (the actor's form just resets — the append arrives via this broadcast).
  after_create_commit :broadcast_comment
  after_destroy_commit :broadcast_removal

  private

  def inherit_household
    self.household ||= todo&.household
  end

  def broadcast_comment
    broadcast_append_to(
      todo,
      target:  ActionView::RecordIdentifier.dom_id(todo, :comments),
      partial: "todo_comments/todo_comment",
      locals:  { todo_comment: self }
    )
  end

  def broadcast_removal
    broadcast_remove_to(todo)
  end
end
