# frozen_string_literal: true
# typed: false

# Base controller for the entire app. Wires up Sorcery for current_user and
# Pundit for authorization. Pantria is single-household-per-instance, so the
# current household is simply {Household.current} -- there is no per-session or
# per-user household selection.
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include LocaleSwitching

  before_action :require_login
  helper_method :current_user, :current_household

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  protect_from_forgery with: :exception

  private

  # @return [Household, nil] The sole household this instance serves.
  def current_household
    @current_household ||= Household.current
  end

  def not_authenticated
    flash[:alert] = t("flash.invalid_login") if request.method != "GET"
    redirect_to login_path
  end

  def user_not_authorized
    flash[:alert] = t("flash.not_authorized")
    redirect_back_or_to(root_path)
  end
end
