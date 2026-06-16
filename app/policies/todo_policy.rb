# frozen_string_literal: true
# typed: true

# Any member may create, view and update todos; only admins may destroy them
# (inherits the ApplicationPolicy defaults). Listed explicitly for clarity.
class TodoPolicy < ApplicationPolicy
  def index?   = household_member?
  def show?    = household_member?
  def create?  = household_member?
  def update?  = household_member?
  def destroy? = household_admin?

  # Moving a todo through its states is a normal member action.
  def transition? = household_member?
end
