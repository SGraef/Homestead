# frozen_string_literal: true
# typed: false

require "stringio"
require "open3"

module Maintenance
  # The upgrade keystone's proof: an N-1 -> N migration smoke test. On a
  # THROWAWAY database it drops everything, migrates to the previous release's
  # version, plants a canary household row plus a real Active Storage blob,
  # migrates to the latest version, then asserts the row survived and the blob
  # is still downloadable.
  #
  # This is what makes "no destructive upgrades" testable: an empty-DB migrate
  # proves nothing; this proves pre-existing data and resolvable blobs survive a
  # real forward migration. Run by `rake homestead:migration_smoke_test` in its
  # own CI job against a dedicated database — never the real one.
  class MigrationSmokeTest
    class Failure < StandardError; end

    CANARY_HOUSEHOLD = "migration-smoke-canary"
    BLOB_BYTES       = "migration-smoke-blob-bytes"

    def self.run!(**) = new(**).run!

    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def run!
      raise Failure, "refusing to run in production" if Rails.env.production?

      ActiveRecord::Migration.verbose = false # keep the CI log readable

      versions = migration_context.migrations.map(&:version).sort
      raise Failure, "need at least two migrations to test N-1 -> N" if versions.size < 2

      n1 = versions[-2]
      n  = versions.last
      log "migration smoke test: N-1=#{n1} -> N=#{n}"

      drop_all_tables!
      migrate_to(n1)
      assert(current_version == n1, "expected DB at N-1 (#{n1}), got #{current_version}")

      household_id = plant_canary_household
      blob_id      = plant_canary_blob
      log "planted canary household ##{household_id} + blob ##{blob_id} at N-1"

      migrate_to(nil) # migrate up to the latest version
      assert(current_version == n, "expected DB at N (#{n}), got #{current_version}")

      assert_household_survived(household_id)
      assert_blob_resolvable(blob_id)

      log "PASS: prior-release data + Active Storage blob survived the upgrade to #{n}."
      n
    end

    private

    def migration_context
      ActiveRecord::Base.connection_pool.migration_context
    end

    def current_version
      migration_context.current_version
    end

    def connection
      ActiveRecord::Base.connection
    end

    def drop_all_tables!
      connection.disable_referential_integrity do
        connection.tables.each { |t| connection.drop_table(t, force: :cascade) }
      end
    end

    # Migrate via a subprocess on the standard `rails db:migrate` path. Running
    # the migrator in-process and twice in one boot trips on migration-class
    # constant loading (e.g. the `API` acronym inflection); a clean subprocess
    # per step sidesteps that entirely.
    def migrate_to(version)
      args = version ? ["db:migrate", "VERSION=#{version}"] : ["db:migrate"]
      out, status = Open3.capture2e("bin/rails", *args, chdir: Rails.root.to_s)
      raise Failure, "`rails #{args.join(" ")}` failed:\n#{out.lines.last(15).join}" unless status.success?

      # The migration ran in another process; drop this process's stale column
      # cache so the Active Storage model reads the post-migration schema.
      ActiveStorage::Blob.reset_column_information
    end

    def plant_canary_household
      connection.insert(
        "INSERT INTO households (name, timezone, created_at, updated_at) " \
        "VALUES (#{connection.quote(CANARY_HOUSEHOLD)}, 'UTC', NOW(), NOW())"
      )
    end

    def plant_canary_blob
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(BLOB_BYTES), filename: "canary.txt", content_type: "text/plain"
      ).id
    end

    def assert_household_survived(id)
      found = connection.select_value(
        "SELECT COUNT(*) FROM households WHERE id = #{id.to_i} AND name = #{connection.quote(CANARY_HOUSEHOLD)}"
      ).to_i
      assert(found == 1, "canary household ##{id} did not survive the migration")
    end

    def assert_blob_resolvable(id)
      blob = ActiveStorage::Blob.find_by(id: id)
      assert(blob.present?, "canary blob row ##{id} did not survive the migration")
      assert(blob.download == BLOB_BYTES, "canary blob ##{id} is no longer downloadable / bytes changed")
    end

    def assert(condition, message)
      raise Failure, message unless condition
    end

    def log(message)
      @logger&.info("[homestead] #{message}")
    end
  end
end
