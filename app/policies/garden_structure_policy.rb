# frozen_string_literal: true
# typed: true

# Structures are captured reality (like the Grundstück outline itself), so
# they follow GardenMapSettingPolicy: everyone sees them on the planner and
# the plan, only household admins change them.
class GardenStructurePolicy < ApplicationPolicy
  def create?  = household_admin?
  def update?  = household_admin?
  def destroy? = household_admin?
end
