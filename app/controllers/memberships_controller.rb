# frozen_string_literal: true
# typed: false

class MembershipsController < ApplicationController
  before_action :set_household

  def create
    authorize @household, :update?
    user = User.find_by(email: params.dig(:membership, :email)&.downcase&.strip)
    return redirect_to(@household, alert: t("notices.user_not_found")) unless user

    @household.memberships.find_or_create_by!(user: user) do |m|
      m.role = params.dig(:membership, :role).presence || "member"
    end
    redirect_to @household, notice: t("notices.member_added")
  end

  def update
    authorize @household, :update?
    membership = @household.memberships.find(params[:id])
    new_role   = params.dig(:membership, :role)

    # Block "demote the only remaining admin" -- the household would then
    # have no admin and become unmanageable.
    if membership.role == "admin" && new_role == "member" && last_admin?(membership)
      redirect_to @household, alert: t("notices.cannot_demote_last_admin")
      return
    end

    if membership.update(role: new_role)
      redirect_to @household, notice: t("notices.member_updated")
    else
      redirect_to @household, alert: membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @household, :update?
    membership = @household.memberships.find(params[:id])
    if membership.role == "admin" && last_admin?(membership)
      redirect_to @household, alert: t("notices.cannot_remove_last_admin")
      return
    end

    membership.destroy
    redirect_to @household, notice: t("notices.member_removed")
  end

  private

  def set_household
    @household = current_user.households.find(params[:household_id])
  end

  # Is `membership` the only admin left in the household?
  def last_admin?(membership)
    membership.household.memberships
              .where(role: "admin")
              .where.not(id: membership.id)
              .none?
  end
end
