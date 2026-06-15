# frozen_string_literal: true
# typed: true

# Base class for all Pundit policies. Pantria is single-household-per-instance,
# so every authenticated user is a member of the one household and has full
# access to its data -- there is no cross-tenant gatekeeping. The only
# distinction left is `household_admin?`, which governs settings, member
# management and destructive deletes.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    raise Pundit::NotAuthorizedError, "must be logged in" unless user

    @user   = user
    @record = record
  end

  def index?    = household_member?
  def show?     = household_member?
  def create?   = household_member?
  def new?      = create?
  def update?   = household_member?
  def edit?     = update?
  def destroy?  = household_admin?

  protected

  # Any authenticated user belongs to the single household. (The constructor
  # already rejects a nil user.)
  def household_member?
    true
  end

  # Admin of the one household this instance serves. Admin status is
  # instance-wide -- it does not depend on the specific record.
  def household_admin?
    household = Household.current
    household.present? && user.admin_of?(household)
  end

  # Every record belongs to the one household, so the scope is unfiltered.
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve
      scope.all
    end
  end
end
