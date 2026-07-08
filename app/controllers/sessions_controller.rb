# frozen_string_literal: true
# typed: false

class SessionsController < ApplicationController
  include LdapAuthentication

  skip_before_action :require_login, only: %i[new create]

  def new; end

  def create
    user = authenticate_for_session
    if user
      flash[:notice] = t("flash.signed_in", email: user.email)
      redirect_to root_path
    else
      flash.now[:alert] = t("flash.invalid_login")
      render :new, status: :unauthorized
    end
  end

  def destroy
    logout
    flash[:notice] = t("flash.signed_out")
    redirect_to login_path
  end

  private

  # LDAP-linked users bind against the directory (while one is configured);
  # everyone else goes through Sorcery's regular password login.
  def authenticate_for_session
    user = User.find_by(email: params[:email].to_s.downcase.strip)
    return ldap_login(user) if user&.ldap_user? && ldap_ready?

    login(params[:email], params[:password], params[:remember_me])
  end

  # Mirrors what Sorcery's `login` does on the local path: activation guard,
  # fresh session (fixation protection), optional remember-me.
  def ldap_login(user)
    return nil unless user.activation_state.nil? || user.activation_state == "active"
    return nil unless ldap_password_valid?(user, params[:password].to_s)

    reset_session
    auto_login(user)
    remember_me! if params[:remember_me].present? && params[:remember_me] != "0"
    user
  end
end
