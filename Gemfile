# frozen_string_literal: true
# typed: ignore

source "https://rubygems.org"

ruby "3.3.6"

gem "rails", "~> 8.0.1"
gem "mysql2", "~> 0.5"
gem "puma", "~> 6.4"

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

group :development, :test do
  gem "rspec-rails", "~> 7.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.5"
  gem "shoulda-matchers", "~> 6.4"
  gem "database_cleaner-active_record", "~> 2.2"
  gem "debug", "~> 1.9", platforms: %i[mri windows]
  gem "dotenv-rails", "~> 3.1"
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
