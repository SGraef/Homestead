# frozen_string_literal: true
# typed: false

if ENV["COVERAGE"] == "1"
  require "simplecov"
  SimpleCov.start "rails" do
    add_filter "/spec/"
    add_filter "/sorbet/"

    # Fixed line-coverage floor (ROADMAP M0c/H1 CI ratchet pt2). Baseline was
    # ~75.9%; the floor sits ~2% below it so a normal PR can't quietly erode
    # coverage, without being so tight it flakes. Enforced only under
    # COVERAGE=1 (the CI rspec job, which runs the whole suite); raise it as
    # coverage climbs. No refuse_coverage_drop — it flakes on partial runs.
    minimum_coverage line: 73
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
