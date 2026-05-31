# frozen_string_literal: true
# typed: false

# Serves the Digital Asset Links file Chrome reads to verify that the
# Android TWA (android/) and this domain are owned by the same party.
# Without a passing verification the TWA falls back to a Chrome Custom
# Tab and shows the URL bar — which defeats the "looks like a native
# app" point of the TWA.
#
# The signing-key SHA-256 fingerprints are supplied via
# `ANDROID_TWA_FINGERPRINTS` (comma-separated). Get the debug-keystore
# fingerprint with `keytool` — see android/README.md.
class WellKnownController < ApplicationController
  skip_before_action :require_login

  def assetlinks
    expires_in 1.hour, public: true
    render json: [{
      relation: ["delegate_permission/common.handle_all_urls"],
      target:   {
        namespace:                "android_app",
        package_name:             ENV.fetch("ANDROID_TWA_PACKAGE", "de.lunawolf.pantria"),
        sha256_cert_fingerprints: fingerprints
      }
    }]
  end

  private

  # `ANDROID_TWA_FINGERPRINTS` accepts multiple values so debug + release
  # keystores can coexist while testing (the production build's
  # fingerprint must be listed too once you sign with a real keystore).
  def fingerprints
    raw = ENV.fetch("ANDROID_TWA_FINGERPRINTS", "")
    raw.split(",").map(&:strip).reject(&:empty?)
  end
end
