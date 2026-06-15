# frozen_string_literal: true
# typed: false

# A comment on a {Todo}. Its body is later scanned for German dates/keywords to
# suggest calendar events (suggest-then-confirm).
class TodoComment < ApplicationRecord
  belongs_to :household
  belongs_to :todo
  belongs_to :user, optional: true

  validates :body, presence: true

  before_validation :inherit_household, on: :create

  private

  def inherit_household
    self.household ||= todo&.household
  end
end
