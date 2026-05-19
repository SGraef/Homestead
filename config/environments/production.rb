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
  config.action_mailer.smtp_settings = {
    address:              ENV.fetch("SMTP_ADDRESS", "localhost"),
    port:                 ENV.fetch("SMTP_PORT", 587).to_i,
    domain:               ENV.fetch("SMTP_DOMAIN", ENV.fetch("APP_HOST", "pantria.example.com")),
    user_name:            ENV["SMTP_USERNAME"].presence,
    password:             ENV["SMTP_PASSWORD"].presence,
    authentication:       ENV.fetch("SMTP_AUTH", "plain").to_sym,
    enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", "true") == "true"
  }.compact

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
end
