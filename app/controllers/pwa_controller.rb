# frozen_string_literal: true
# typed: false

# Serves the Web App Manifest and Service Worker for installable-PWA
# support. Both endpoints are public -- the service worker installs
# before a session exists, so requiring login here would block install
# entirely.
class PwaController < ApplicationController
  skip_before_action :require_login

  # Rails blocks JS responses to non-XHR GETs by default
  # (`InvalidCrossOriginRequest`) to stop drive-by <script> includes
  # from exfiltrating logged-in data. The service worker is by design
  # fetched as a top-level script and carries no user data, so we
  # opt out for this action only.
  skip_forgery_protection only: :service_worker

  def manifest
    expires_in 1.hour, public: true
    render template:     "pwa/manifest",
           formats:      :json,
           layout:       false,
           content_type: "application/manifest+json"
  end

  def service_worker
    # The SW file must be served fresh enough that bumping CACHE_VERSION
    # actually takes effect; 5 minutes balances that against repeated
    # navigation hits.
    expires_in 5.minutes, public: true
    render template:     "pwa/service_worker",
           formats:      :js,
           layout:       false,
           content_type: "application/javascript"
  end

  def offline
    expires_in 1.hour, public: true
    render layout: false
  end
end
