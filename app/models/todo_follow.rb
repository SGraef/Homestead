# frozen_string_literal: true
# typed: false

# A member's follow on a todo. Followers receive notifications on meaningful
# changes (status, assignee, new comment).
class TodoFollow < ApplicationRecord
  belongs_to :household
  belongs_to :todo
  belongs_to :user

  validates :user_id, uniqueness: { scope: :todo_id }

  before_validation :inherit_household, on: :create

  private

  def inherit_household
    self.household ||= todo&.household
  end
end
