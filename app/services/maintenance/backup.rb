# frozen_string_literal: true
# typed: false

require "open3"
require "fileutils"

module Maintenance
  # Captures a point-in-time backup of everything an upgrade could damage: the
  # MySQL database (logical dump) and the Active Storage blobs (the receipt
  # images and any other attachments). Written under BACKUP_DIR (default
  # `<app>/backups/<timestamp>/`), deliberately OUTSIDE the Active Storage root
  # so a backup never recursively copies prior backups.
  #
  # Used by `rake homestead:backup` and as the pre-upgrade step of
  # `rake homestead:upgrade`, so a failed migration is always recoverable.
  class Backup
    class Error < StandardError; end

    def self.call(**) = new(**).call

    # @param root [String, Pathname, nil] backup destination root
    # @param timestamp [String, nil] subdirectory name (defaults to UTC now)
    def initialize(root: nil, timestamp: nil, logger: Rails.logger)
      @root      = Pathname(root || ENV.fetch("BACKUP_DIR", Rails.root.join("backups").to_s))
      @timestamp = timestamp || Time.current.utc.strftime("%Y%m%d-%H%M%S")
      @logger    = logger
    end

    # @return [Pathname] the directory the backup was written to
    def call
      dir = @root.join(@timestamp)
      FileUtils.mkdir_p(dir)
      dump_database(dir.join("database.sql"))
      copy_active_storage(dir.join("active_storage"))
      @logger&.info("[homestead] backup written to #{dir}")
      dir
    end

    private

    def dump_database(path)
      cfg  = ActiveRecord::Base.connection_db_config.configuration_hash
      args = [
        "mysqldump",
        "--host=#{cfg[:host] || "127.0.0.1"}",
        "--port=#{cfg[:port] || 3306}",
        "--user=#{cfg[:username]}",
        "--single-transaction", # consistent InnoDB snapshot without locking
        "--no-tablespaces",     # avoids needing the PROCESS privilege on MySQL 8
        cfg[:database]
      ]
      # Pass the password via env (MYSQL_PWD) so it never appears in the process
      # list / argv.
      out, err, status = Open3.capture3({ "MYSQL_PWD" => cfg[:password].to_s }, *args)
      raise Error, "mysqldump failed: #{err.to_s.strip.presence || "exit #{status.exitstatus}"}" unless status.success?

      File.binwrite(path, out)
    rescue Errno::ENOENT
      raise Error, "mysqldump not found in PATH (install the MySQL client)"
    end

    # Copy the Active Storage blobs when the configured service is local Disk.
    # Cloud services (S3, etc.) are backed up by the provider and have no local
    # root to copy.
    def copy_active_storage(dest)
      service = ActiveStorage::Blob.service
      root    = service.respond_to?(:root) ? service.root : nil
      unless root && Dir.exist?(root)
        @logger&.info("[homestead] no local Active Storage root to back up (service: #{service.class})")
        return
      end

      FileUtils.mkdir_p(dest)
      # copy the contents of the storage root into dest/
      FileUtils.cp_r(Dir.glob(File.join(root, "*")), dest)
    end
  end
end
