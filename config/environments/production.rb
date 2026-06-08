# frozen_string_literal: true
# typed: ignore

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true

  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?
  config.assume_ssl = true
  config.force_ssl = true

  config.log_tags = [:request_id]
  config.logger = ActiveSupport::Logger.new($stdout)
                                       .tap { |l| l.formatter = Logger::Formatter.new }
                                       .then { |l| ActiveSupport::TaggedLogging.new(l) }
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  config.active_storage.service = :local
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "pantria.example.com") }
  config.action_mailer.delivery_method = :smtp
  # SMTP_USERNAME / SMTP_PASSWORD are optional -- a local relay
  # (postfix on the same box, Mailpit in dev-like envs, a mailhog
  # sidecar, ...) typically doesn't authenticate. Only enable
  # authentication when BOTH credentials are present; otherwise drop
  # the auth keys entirely. Setting `authentication: :plain` while
  # leaving user_name nil raises ArgumentError on the first send
  # ("SMTP-AUTH requested but missing user name") and that bubbles
  # up to whichever controller triggered the mail.
  smtp_user = ENV["SMTP_USERNAME"].presence
  smtp_pass = ENV["SMTP_PASSWORD"].presence
  config.action_mailer.smtp_settings = {
    address:              ENV.fetch("SMTP_ADDRESS", "localhost"),
    port:                 ENV.fetch("SMTP_PORT", 587).to_i,
    domain:               ENV.fetch("SMTP_DOMAIN", ENV.fetch("APP_HOST", "pantria.example.com")),
    enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", "true") == "true"
  }
  if smtp_user && smtp_pass
    config.action_mailer.smtp_settings.merge!(
      user_name:      smtp_user,
      password:       smtp_pass,
      authentication: ENV.fetch("SMTP_AUTH", "plain").to_sym
    )
  end

  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]

  # Use solid_cache when it's bundled, fall back to in-process memory
  # otherwise. Inline `rescue` only catches StandardError, but LoadError
  # is a ScriptError -- so we have to require + rescue explicitly.
  config.cache_store =
    begin
      require "solid_cache"
      :solid_cache_store
    rescue LoadError
      :memory_store
    end

  config.hosts.clear
  config.hosts << ENV.fetch("APP_HOST", "pantria.example.com")
  # Docker's HEALTHCHECK curls http://localhost:3000/up from inside the
  # container -- that Host header isn't in the whitelist, so without this
  # the health probe gets a 403 and the orchestrator marks the container
  # unhealthy. Skip host auth for the health endpoint only; the rest of
  # the app keeps its DNS-rebinding guard.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
