# frozen_string_literal: true
# typed: ignore

require_relative "config/environment"

run Rails.application
Rails.application.load_server
