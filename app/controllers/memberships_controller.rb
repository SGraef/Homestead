# frozen_string_literal: true
# typed: false

class MembershipsController < ApplicationController
  before_action :set_household

  def create
    authorize @household, :update?
    email = params.dig(:membership, :email).to_s.downcase.strip
    role  = params.dig(:membership, :role).presence || "member"
    user  = User.find_by(email: email)

    if user
      @household.memberships.find_or_create_by!(user: user) { |m| m.role = role }
      redirect_to household_path, notice: t("notices.member_added")
    elsif email.match?(URI::MailTo::EMAIL_REGEXP)
      # No account yet: self-registration is closed, so issue a tokened invite.
      invitation = Invitation.invite!(household: @household, email: email,
                                      role: role, invited_by: current_user)
      UserMailer.invitation_email(invitation, invitation.plaintext).deliver_later
      redirect_to household_path, notice: t("notices.member_invited", email: email)
    else
      redirect_to household_path, alert: t("notices.invalid_email")
    end
  end

  def update
    authorize @household, :update?
    membership = @household.memberships.find(params[:id])
    new_role   = params.dig(:membership, :role)

    # Block "demote the only remaining admin" -- the household would then
    # have no admin and become unmanageable.
    if membership.role == "admin" && new_role == "member" && last_admin?(membership)
      redirect_to household_path, alert: t("notices.cannot_demote_last_admin")
      return
    end

    if membership.update(role: new_role)
      redirect_to household_path, notice: t("notices.member_updated")
    else
      redirect_to household_path, alert: membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @household, :update?
    membership = @household.memberships.find(params[:id])
    if membership.role == "admin" && last_admin?(membership)
      redirect_to household_path, alert: t("notices.cannot_remove_last_admin")
      return
    end

    membership.destroy
    redirect_to household_path, notice: t("notices.member_removed")
  end

  private

  def set_household
    @household = Household.current
    raise ActiveRecord::RecordNotFound unless @household
  end

  # Is `membership` the only admin left in the household?
  def last_admin?(membership)
    membership.household.memberships
              .where(role: "admin")
              .where.not(id: membership.id)
              .none?
  end
end
