# frozen_string_literal: true
# typed: false

# Standard Sorcery `reset_password` flow:
#
#   GET  /password_resets/new       — request form (enter email)
#   POST /password_resets           — generate token + send email
#   GET  /password_resets/:token/edit  — link from the email
#   PATCH /password_resets/:token   — submit the new password
class PasswordResetsController < ApplicationController
  skip_before_action :require_login

  def new; end

  def edit
    @user = User.load_from_reset_password_token(params[:token])
    redirect_to(new_password_reset_path, alert: t("password_reset.invalid")) unless @user
  end

  def create
    user = User.find_by(email: params[:email].to_s.downcase.strip)
    # LDAP-linked accounts get no reset mail: their password lives in the
    # directory. Same generic notice either way (don't leak which addresses
    # exist, nor which are LDAP-managed).
    user.deliver_reset_password_instructions! if user && !user.ldap_user?
    redirect_to login_path, notice: t("password_reset.email_sent")
  end

  def update
    @user = User.load_from_reset_password_token(params[:token])
    return redirect_to(new_password_reset_path, alert: t("password_reset.invalid")) unless @user
    # Token issued before the account was linked to LDAP: the local password
    # is dormant now, so resetting it here would just mislead.
    return redirect_to(login_path, alert: t("password_reset.ldap_managed")) if @user.ldap_user?

    @user.password_confirmation = params.dig(:user, :password_confirmation)
    if @user.change_password(params.dig(:user, :password))
      redirect_to login_path, notice: t("password_reset.success")
    else
      render :edit, status: :unprocessable_content
    end
  end
end
