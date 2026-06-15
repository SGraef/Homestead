# frozen_string_literal: true
# typed: true

# The household is a singleton settings resource. Any member can view it;
# only admins can edit it. There is no create/destroy (the household is created
# at first-run sign-up) and no list scope.
class HouseholdPolicy < ApplicationPolicy
  def show?   = household_member?
  def edit?   = household_admin?
  def update? = household_admin?
end
