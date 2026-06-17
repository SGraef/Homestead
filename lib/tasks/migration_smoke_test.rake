# frozen_string_literal: true

namespace :homestead do
  desc "N-1 -> N migration smoke test on a THROWAWAY DB (proves upgrades keep data + blobs)"
  task migration_smoke_test: :environment do
    Maintenance::MigrationSmokeTest.run!
    puts "[homestead] migration smoke test PASSED"
  rescue Maintenance::MigrationSmokeTest::Failure => e
    warn "[homestead] migration smoke test FAILED: #{e.message}"
    exit 1
  end
end
