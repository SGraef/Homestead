# frozen_string_literal: true
# typed: true

# Join model between {User} and {Household} carrying the user's role within
# that household. Used by Pundit to authorize household-scoped actions.
class Membership < ApplicationRecord
  ROLES = %w[admin member].freeze

  belongs_to :user
  belongs_to :household

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :household_id }
end
