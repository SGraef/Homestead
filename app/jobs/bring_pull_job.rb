# frozen_string_literal: true
# typed: true

# Pulls the household's Bring! list and reconciles into the local grocery
# items. Triggered manually (the "Sync now" button on /bring_connection)
# AND scheduled periodically (e.g. every 5 minutes via cron / solid_queue
# recurring jobs) for households that have Bring! connected.
class BringPullJob < ApplicationJob
  queue_as :default

  retry_on Bring::Error, attempts: 3, wait: :polynomially_longer
  discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound, Bring::AuthError

  # Enqueue a pull for the single household, if it has Bring! connected.
  # Convenient one-liner for cron:
  #   bin/rails runner 'BringPullJob.sync_all'
  # Scoped to {Household.current} so a database upgraded from the old
  # multi-household schema never syncs orphaned households' connections.
  def self.sync_all
    household = Household.current
    return unless household

    BringConnection.where(household_id: household.id)
                   .where.not(access_token: [nil, ""])
                   .where.not(default_list_uuid: [nil, ""])
                   .find_each { |c| perform_later(c.household_id) }
  end

  # @param household_id [Integer]
  def perform(household_id)
    household  = Household.find(household_id)
    connection = household.bring_connection
    return unless connection&.connected?

    Bring::Pull.new(connection).call
  rescue Bring::Error => e
    Household.find_by(id: household_id)&.bring_connection
             &.update_columns(last_error: e.message.first(500), updated_at: Time.current)
    raise
  end
end
