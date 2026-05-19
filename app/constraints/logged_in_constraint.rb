# frozen_string_literal: true
# typed: true

# Routing constraint: only matches when the request session has a Sorcery
# user. Used to gate mounted engines (e.g. SolidQueueDashboard) that don't
# inherit ApplicationController#require_login. Anonymous requests fall
# through to the default 404, which is fine for an admin-ish surface --
# we don't want to advertise its existence with a redirect.
class LoggedInConstraint
  def self.matches?(request)
    request.session[:user_id].present?
  end
end
