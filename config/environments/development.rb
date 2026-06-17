# frozen_string_literal: true
# typed: ignore

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.cache_store = :memory_store
    config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false
    config.cache_store = :null_store
  end

  config.active_storage.service = :local
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
  # Write rendered emails to tmp/mails/ in dev so we can inspect activation
  # and reset-password messages without running an SMTP catcher.
  config.action_mailer.delivery_method = :file
  config.action_mailer.file_settings   = { location: Rails.root.join("tmp/mails") }

  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_job.verbose_enqueue_logs = true

  config.action_view.annotate_rendered_view_with_filenames = true
  config.action_controller.raise_on_missing_callback_actions = true

  config.hosts << "homestead.localhost"
  config.hosts << "web"
  # docker-compose.test.yml service name used by the Cypress runner.
  config.hosts << "app-e2e"

  # Phones on the LAN reach the dev server via the host's private IP, which
  # would otherwise be rejected by Rails' DNS-rebinding guard. Allow the
  # three RFC1918 ranges in development; the guard stays strict in
  # production (see config/environments/production.rb).
  config.hosts << /\A192\.168\.\d+\.\d+\z/
  config.hosts << /\A10\.\d+\.\d+\.\d+\z/
  config.hosts << /\A172\.(1[6-9]|2\d|3[01])\.\d+\.\d+\z/
end
