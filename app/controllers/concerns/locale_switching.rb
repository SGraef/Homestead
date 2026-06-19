# frozen_string_literal: true
# typed: false

# Resolves the active locale per request, with the precedence:
#   1. `?locale=…` query param (an explicit switch; also saved — see below)
#   2. the logged-in user's saved preference (`users.locale`)
#   3. session value (covers logged-out visitors across a single session)
#   4. `Accept-Language` header
#   5. `I18n.default_locale` (German)
#
# A valid `?locale=…` switch is persisted to the user's account (and the
# session), so the choice follows the user across sessions and devices rather
# than living only in this browser.
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

  def switch_locale(&)
    locale = resolve_locale
    remember_locale(locale)
    I18n.with_locale(locale, &)
  end

  # Persist an explicit, valid `?locale=…` switch to the session and, when
  # signed in, to the user's account. Only fires on a real switch so normal
  # requests don't write on every page load.
  def remember_locale(locale)
    return if params[:locale].blank?
    return unless I18n.available_locales.include?(params[:locale].to_s.to_sym)

    session[:locale] = locale.to_s
    return unless current_user && current_user.locale != locale.to_s

    current_user.update_column(:locale, locale.to_s)
  end

  def resolve_locale
    candidates = [
      params[:locale],
      current_user&.preferred_locale,
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
