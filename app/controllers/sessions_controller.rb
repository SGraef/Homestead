# frozen_string_literal: true
# typed: true

class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new; end

  def create
    user = login(params[:email], params[:password], params[:remember_me])
    if user
      session[:household_id] = user.default_household&.id
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
end
