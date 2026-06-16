# frozen_string_literal: true
# typed: true

# Any member may create/edit events; only admins may delete (mirrors TodoPolicy).
class CalendarEventPolicy < ApplicationPolicy
  def show?    = household_member?
  def create?  = household_member?
  def update?  = household_member?
  def destroy? = household_admin?
end
