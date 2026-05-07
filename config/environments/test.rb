# frozen_string_literal: true
# typed: ignore

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?

  config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{1.hour.to_i}" }

  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store

  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false

  # Tests use the in-memory :test adapter (so `have_enqueued_job` matchers
  # work) — production and dev use Solid Queue (set in application.rb).
  config.active_job.queue_adapter = :test

  config.active_storage.service = :test
  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: "www.example.com" }

  config.active_support.deprecation = :stderr
  config.action_controller.raise_on_missing_callback_actions = true
end
