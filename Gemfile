# frozen_string_literal: true
# typed: ignore

source "https://rubygems.org"

ruby "3.3.6"

gem "rails", "~> 8.0.1"
gem "mysql2", "~> 0.5"
gem "puma", "~> 7.2"

# Hotwire frontend
gem "turbo-rails", "~> 2.0"
gem "stimulus-rails", "~> 1.3"
gem "importmap-rails", "~> 2.0"
gem "propshaft", "~> 1.0"

# Authentication & authorization
gem "sorcery", "~> 0.17"
gem "pundit", "~> 2.4"

# JSON serialization for the REST API
gem "jsonapi-serializer", "~> 2.2"
gem "rack-cors", "~> 2.0"

# Static type checking (Sorbet)
gem "sorbet-static-and-runtime", "~> 0.5"
gem "tapioca", "~> 0.16", require: false

# Documentation
gem "yard", "~> 0.9", require: false

# Misc
gem "bcrypt", "~> 3.1"
gem "bootsnap", "~> 1.18", require: false
gem "image_processing", "~> 1.13"

# Background jobs (Rails 8 native, DB-backed). Worker runs in its own
# container; recurring schedule lives in config/recurring.yml.
gem "solid_queue", "~> 1.0"
# /jobs dashboard for Solid Queue. Mounted in routes.rb behind a
# require-login gate.
gem "solid_queue_dashboard"

# DB-backed Action Cable pub/sub (no Redis container). Powers live Turbo Stream
# updates (todo comments, notification bell). Stored in the primary database,
# consistent with Solid Queue.
gem "solid_cable", "~> 3.0"

# Web Push (VAPID) delivery for PWA notifications. Pure Ruby, no native deps.
gem "web-push", "~> 3.0"

group :development, :test do
  gem "rspec-rails", "~> 7.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.5"
  gem "shoulda-matchers", "~> 6.4"
  gem "database_cleaner-active_record", "~> 2.2"
  gem "debug", "~> 1.9", platforms: %i[mri windows]
  gem "dotenv-rails", "~> 3.1"
  # de/en translation parity guard (enforced by spec/i18n_parity_spec.rb)
  gem "i18n-tasks", "~> 1.0", require: false
end

group :development do
  gem "web-console", "~> 4.2"
  gem "rubocop-rails", "~> 2.27", require: false
  gem "rubocop-rspec", "~> 3.2", require: false
  gem "spring", "~> 4.2"
end

group :test do
  gem "capybara", "~> 3.40"
  gem "selenium-webdriver", "~> 4.27"
  gem "webmock", "~> 3.24"
  gem "simplecov", "~> 0.22", require: false
  gem "rspec_junit_formatter", "~> 0.6", require: false
end

# OpenTelemetry: traces (GA), metrics (GA), logs (experimental at time
# of writing but usable). All require: false — the initializer at
# config/initializers/opentelemetry.rb requires + boots them only when
# OTEL_EXPORTER_OTLP_ENDPOINT is set, so the SDK doesn't load (or
# allocate exporter threads) in CI / local dev unless explicitly
# enabled. See docs/OBSERVABILITY.md.
gem "opentelemetry-sdk", "~> 1.6", require: false
gem "opentelemetry-exporter-otlp", "~> 0.30", require: false
gem "opentelemetry-instrumentation-all", "~> 0.74", require: false
gem "opentelemetry-metrics-sdk", "~> 0.6", require: false
gem "opentelemetry-metrics-api", "~> 0.4", require: false
gem "opentelemetry-exporter-otlp-metrics", "~> 0.6", require: false
gem "opentelemetry-logs-sdk", "~> 0.3", require: false
gem "opentelemetry-logs-api", "~> 0.2", require: false
gem "opentelemetry-exporter-otlp-logs", "~> 0.3", require: false
