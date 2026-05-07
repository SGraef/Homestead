# frozen_string_literal: true
# typed: ignore

require_relative "config/application"

Rails.application.load_tasks

begin
  require "yard"
  YARD::Rake::YardocTask.new do |t|
    t.files = ["app/**/*.rb", "lib/**/*.rb"]
    t.options = ["--output-dir", "doc/yard"]
  end
rescue LoadError
  # YARD only available in dev / docs builds
end
