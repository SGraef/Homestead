# frozen_string_literal: true

# Homestead runs single-household-per-instance. If a database upgraded from the
# old multi-household schema still contains more than one household, Homestead
# silently serves only the oldest one (Household.current). Surface that loudly
# at boot so an operator notices the orphaned data and can decide whether to
# merge it (see `rake homestead:single_household:merge`).
#
# This must NEVER raise during boot: it has to survive `db:create`,
# `db:migrate` and `assets:precompile`, where the database or the `households`
# table may not exist yet. We therefore run after initialization, guard on the
# table's existence, and rescue every "DB not ready" error class.
Rails.application.config.after_initialize do
  next if defined?(Rails::Console) # noisy in `rails c`; the warning targets servers/jobs

  begin
    next unless ActiveRecord::Base.connection.table_exists?("households")

    count = Household.count
    next if count <= 1

    canonical = Household.current
    message = "[Homestead] This instance is single-household, but the database " \
              "contains #{count} households. Serving only ##{canonical&.id} " \
              "(#{canonical&.name.inspect}). The other #{count - 1} household(s) " \
              "and their data are hidden but NOT deleted. Run " \
              "`rake homestead:single_household:merge` to fold them into the " \
              "canonical household, or ignore this if intentional."
    Rails.logger.warn(message)
    warn(message)
  rescue ActiveRecord::NoDatabaseError,
         ActiveRecord::StatementInvalid,
         ActiveRecord::ConnectionNotEstablished
    # Database not created/migrated yet (db:create, db:migrate, assets:precompile).
    # Nothing to check; stay silent.
  end
end
