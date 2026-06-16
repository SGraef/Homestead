# frozen_string_literal: true
# typed: true

# Any member may comment. A comment may be removed by its author or an admin.
class TodoCommentPolicy < ApplicationPolicy
  def create?  = household_member?

  def destroy?
    household_admin? || record.user_id == user.id
  end
end
