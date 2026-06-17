# frozen_string_literal: true
# typed: false

# Rack::Attack throttles abusive traffic on the auth + API surface. Homestead's
# deployment posture is internet-exposed (behind TLS), so login, password-reset,
# token-lookup, invite-activation and push-subscribe endpoints are all reachable
# by anyone and must be rate-limited against brute-force / credential-stuffing /
# email-bombing.
#
# Counters live in Rails.cache (Solid Cache, DB-backed) in production so the
# limit is shared across Puma workers. In test we use a private in-memory store
# and keep Rack::Attack disabled by default (the rate-limiting spec opts in),
# because the test cache is a null store and a process-wide IP counter would
# otherwise leak throttle state across unrelated request specs.

# --- Backing store -----------------------------------------------------------
Rack::Attack.cache.store =
  if Rails.env.test?
    ActiveSupport::Cache::MemoryStore.new
  else
    Rails.cache
  end

# --- Throttles ---------------------------------------------------------------

# Interactive login (web): cap per IP and, separately, per submitted email so
# a single account can't be brute-forced from rotating IPs.
Rack::Attack.throttle("login/ip", limit: 10, period: 20.seconds) do |req|
  req.ip if req.post? && req.path == "/login"
end

Rack::Attack.throttle("login/email", limit: 5, period: 20.seconds) do |req|
  req.params["email"].to_s.downcase.strip.presence if req.post? && req.path == "/login"
end

# API token issuance (bearer-token auth lives behind this).
Rack::Attack.throttle("api_login/ip", limit: 10, period: 20.seconds) do |req|
  req.ip if req.post? && req.path == "/api/v1/sessions"
end

# Password-reset + activation-resend requests trigger outbound email — throttle
# to prevent using us as an email bomb.
Rack::Attack.throttle("password_reset/ip", limit: 5, period: 60.seconds) do |req|
  req.ip if req.post? && req.path == "/password_resets"
end

Rack::Attack.throttle("activation_resend/ip", limit: 5, period: 60.seconds) do |req|
  req.ip if req.post? && req.path == "/activations"
end

# Token-bearing lookups (invite / activation / password-reset edit) — throttle
# by IP so the opaque tokens can't be guessed by brute force.
Rack::Attack.throttle("token_lookup/ip", limit: 30, period: 60.seconds) do |req|
  if req.path.start_with?("/invitations/", "/activate/") ||
     req.path.match?(%r{\A/password_resets/[^/]+})
    req.ip
  end
end

# PWA push subscription writes.
Rack::Attack.throttle("push_subscribe/ip", limit: 30, period: 60.seconds) do |req|
  req.ip if req.post? && req.path == "/push_subscriptions"
end

# General ceiling on the JSON API per IP (defence in depth on top of the
# per-action throttles above).
Rack::Attack.throttle("api/ip", limit: 300, period: 60.seconds) do |req|
  req.ip if req.path.start_with?("/api/")
end

# --- Response ----------------------------------------------------------------

# Return 429 with a Retry-After hint. JSON for /api/*, plain text otherwise.
Rack::Attack.throttled_responder = lambda do |req|
  match    = req.env["rack.attack.match_data"] || {}
  period   = match[:period] || 60
  api      = req.path.start_with?("/api/")
  headers  = {
    "Content-Type" => api ? "application/json" : "text/plain",
    "Retry-After"  => period.to_s
  }
  body = api ? %({"error":"Too many requests. Retry later."}) : "Too many requests. Retry later.\n"
  [429, headers, [body]]
end

# Keep throttling out of the way of the test suite unless a spec opts in
# (`Rack::Attack.enabled = true`). Production/development run with it on.
Rack::Attack.enabled = false if Rails.env.test?
