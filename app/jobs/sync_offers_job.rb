# frozen_string_literal: true
# typed: false

# Runs {OfferSyncer} for one household. Used both ad-hoc (manual "Sync now"
# button on the Offers page) and as a fan-out target from {SyncAllOffersJob}.
class SyncOffersJob < ApplicationJob
  queue_as :default

  # @param household_id [Integer]
  def perform(household_id)
    household = Household.find_by(id: household_id)
    return if household&.postal_code.to_s.strip.blank?

    result = OfferSyncer.new(household).call
    return unless result

    # Now that offers are fresh, alert members about any that match their
    # watchlist (deduped per offer, gated by each member's preferences).
    watch_hits = Reminders::OfferWatchScanner.run(household)

    Rails.logger.info(
      "[SyncOffersJob] household=#{household.id} " \
      "created=#{result.created} updated=#{result.updated} expired=#{result.expired} " \
      "watch_hits=#{watch_hits}"
    )
  end
end
