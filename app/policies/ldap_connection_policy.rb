# frozen_string_literal: true
# typed: true

# The LDAP connection holds service-account credentials and decides how the
# whole household authenticates -- admin-only, like the paperless connection.
class LdapConnectionPolicy < ApplicationPolicy
  def show?    = household_admin?
  def new?     = household_admin?
  def create?  = household_admin?
  def update?  = household_admin?
  def destroy? = household_admin?
  def test?    = household_admin?
end
