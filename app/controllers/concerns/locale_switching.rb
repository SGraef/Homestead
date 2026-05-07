# frozen_string_literal: true
# typed: true

# Resolves the active locale per request, with the precedence:
#   1. `?locale=…` query param (and persisted into the session for next time)
#   2. session value the user previously chose
#   3. `Accept-Language` header
#   4. `I18n.default_locale` (German)
#
# Mixed into {ApplicationController}; API controllers do not include it -- the
# REST API responds in whatever locale the client passes via header.
module LocaleSwitching
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
  end

  def default_url_options
    if I18n.locale && I18n.locale != I18n.default_locale
      { locale: I18n.locale }
    else
      {}
    end
  end

  private

  def switch_locale(&action)
    locale = resolve_locale
    session[:locale] = locale.to_s if params[:locale].present?
    I18n.with_locale(locale, &action)
  end

  def resolve_locale
    candidates = [
      params[:locale],
      session[:locale],
      accept_language_locale,
      I18n.default_locale
    ]
    candidates.compact.map(&:to_sym).find { |l| I18n.available_locales.include?(l) } ||
      I18n.default_locale
  end

  def accept_language_locale
    request.env["HTTP_ACCEPT_LANGUAGE"]
           .to_s
           .scan(/[a-z]{2}/i)
           .map(&:downcase)
           .find { |l| I18n.available_locales.map(&:to_s).include?(l) }
  end
end
