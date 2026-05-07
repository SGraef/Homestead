# frozen_string_literal: true
# typed: false

if ENV["COVERAGE"] == "1"
  require "simplecov"
  SimpleCov.start "rails" do
    add_filter "/spec/"
    add_filter "/sorbet/"
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |e| e.syntax = :expect }
  config.mock_with(:rspec) { |m| m.verify_partial_doubles = true }
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = false
  config.profile_examples = 5
  config.order = :random
  Kernel.srand config.seed
end
