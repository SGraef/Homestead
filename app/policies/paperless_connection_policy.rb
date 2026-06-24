# frozen_string_literal: true
# typed: true

# The paperless connection holds an API token and points outbound traffic at a
# household-controlled host -- admin-only, like the calendar connection.
class PaperlessConnectionPolicy < ApplicationPolicy
  def show?    = household_admin?
  def new?     = household_admin?
  def create?  = household_admin?
  def update?  = household_admin?
  def destroy? = household_admin?
  def test?    = household_admin?
end
