# frozen_string_literal: true
# typed: false

# Base controller for the entire app. Wires up Sorcery for current_user and
# Pundit for authorization. The current household is resolved from the
# `:household_id` session key (set after login).
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include LocaleSwitching

  before_action :require_login
  helper_method :current_user, :current_household

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  protect_from_forgery with: :exception

  private

  # @return [Household, nil] The household actively in use this session.
  def current_household
    @current_household ||= begin
      id = session[:household_id]
      household = current_user&.households&.find_by(id: id) if id
      household || current_user&.default_household
    end
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
