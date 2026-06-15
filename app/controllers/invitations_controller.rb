# frozen_string_literal: true
# typed: false

# Handles the tokened invite link from {UserMailer#invitation_email}:
#
#   GET   /invitations/:token   — accept form (set name + password)
#   PATCH /invitations/:token   — create the account + membership, log in
#
# Plus the admin-only revoke action on the household settings page.
class InvitationsController < ApplicationController
  # The accept flow is reached by logged-out invitees; revoke is admin-only.
  skip_before_action :require_login, only: %i[show update]

  def show
    @invitation = Invitation.authenticate(params[:token])
    return redirect_to(login_path, alert: t("invitation.invalid")) unless @invitation

    @token = params[:token]
    @user  = User.new(email: @invitation.email)
  end

  def update
    @invitation = Invitation.authenticate(params[:token])
    return redirect_to(login_path, alert: t("invitation.invalid")) unless @invitation

    @token = params[:token]

    user = @invitation.accept!(
      name:                  params.dig(:user, :name),
      password:              params.dig(:user, :password),
      password_confirmation: params.dig(:user, :password_confirmation)
    )
    auto_login(user)
    redirect_to root_path, notice: t("invitation.accepted")
  rescue ActiveRecord::RecordInvalid => e
    @user = e.record
    render :show, status: :unprocessable_content
  end

  # DELETE /household/invitations/:id — admin revokes a pending invitation.
  def destroy
    authorize Household.current, :update?
    Household.current.invitations.find(params[:id]).destroy
    redirect_to household_path, notice: t("notices.invitation_revoked")
  end
end
