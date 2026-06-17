# frozen_string_literal: true

namespace :homestead do
  desc "Back up the database + Active Storage to BACKUP_DIR/<timestamp>/"
  task backup: :environment do
    dir = Maintenance::Backup.call
    puts "[homestead] backup written to #{dir}"
  end

  desc "Safe upgrade: back up first, then run pending migrations"
  task upgrade: :environment do
    dir = Maintenance::Backup.call
    puts "[homestead] pre-upgrade backup at #{dir}"

    begin
      Rake::Task["db:migrate"].invoke
      puts "[homestead] migrations applied — upgrade complete."
    rescue StandardError => e
      warn "[homestead] migration FAILED: #{e.class}: #{e.message}"
      warn "[homestead] your data is safe in the pre-upgrade backup. To roll back:"
      warn "  1. mysql -h <host> -u <user> -p <database> < #{dir.join("database.sql")}"
      warn "  2. restore the blobs in #{dir.join("active_storage")} to your Active Storage root"
      warn "  3. redeploy the previous image tag"
      raise
    end
  end
end
