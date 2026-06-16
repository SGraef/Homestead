# frozen_string_literal: true
# typed: true

# The external-calendar connection holds OAuth secrets and affects every
# member's calendar — admin-only.
class CalendarConnectionPolicy < ApplicationPolicy
  def show?   = household_admin?
  def edit?   = household_admin?
  def update? = household_admin?
end
