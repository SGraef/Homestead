# frozen_string_literal: true
# typed: true

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

  def destroy
    authorize @household, :update?
    @household.memberships.find(params[:id]).destroy
    redirect_to @household, notice: t("notices.member_removed")
  end

  private

  def set_household
    @household = current_user.households.find(params[:household_id])
  end
end
