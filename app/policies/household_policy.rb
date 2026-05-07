# frozen_string_literal: true
# typed: true

class HouseholdPolicy < ApplicationPolicy
  def show?    = household_member?
  def create?  = true
  def update?  = household_admin?
  def destroy? = household_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(:memberships).where(memberships: { user_id: user.id }).distinct
    end
  end
end
