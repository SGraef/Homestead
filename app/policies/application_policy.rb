# frozen_string_literal: true
# typed: true

# Base class for all Pundit policies. Records authorization decisions against
# the user's household memberships -- a user may only act on records that
# belong to a household they are a member of.
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

  # @return [Household, nil]
  def household_for(record)
    return record if record.is_a?(Household)
    return record.household if record.respond_to?(:household)

    nil
  end

  def household_member?
    h = household_for(record)
    return true if h.nil? # class-level checks fall through

    user.households.exists?(id: h.id)
  end

  def household_admin?
    h = household_for(record)
    return false unless h

    user.admin_of?(h)
  end

  # Default scope: only records belonging to households the user is a member of.
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve
      household_ids = user.households.select(:id)
      if scope.respond_to?(:column_names) && scope.column_names.include?("household_id")
        scope.where(household_id: household_ids)
      else
        scope.all
      end
    end
  end
end
