# frozen_string_literal: true
# typed: ignore

require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module Pantria
  # Top-level application namespace.
  #
  # Pantria is a Household ERP focused on food storage, multi-store grocery
  # tracking and barcode-driven inventory updates.
  class Application < Rails::Application
    config.load_defaults 8.0

    config.autoload_lib(ignore: %w[assets tasks])

    config.api_only = false
    config.time_zone = "Europe/Berlin"
    config.active_record.default_timezone = :utc

    # ActiveJob through Solid Queue (DB-backed, polled by the `worker`
    # docker-compose service). Tests still use :test (set per-env).
    config.active_job.queue_adapter = :solid_queue

    # Internationalization. German is the default; English is the fallback.
    config.i18n.default_locale     = :de
    config.i18n.available_locales  = %i[de en]
    config.i18n.fallbacks          = [:en]
    config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}")]

    config.generators do |g|
      g.test_framework :rspec,
                       fixtures:      false,
                       view_specs:    false,
                       helper_specs:  false,
                       routing_specs: false
      g.factory_bot dir: "spec/factories"
    end
  end
end
