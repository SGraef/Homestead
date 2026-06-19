# frozen_string_literal: true
# typed: false

module Reminders
  # Notifies members when a current offer matches one of the household's
  # {OfferWatchlistEntry} patterns — the "something you watch is on sale" signal
  # of the proactive-reminders engine. Runs after each offer sync
  # ({SyncOffersJob}); reuses the {Notification} ledger (bell + push) and is
  # gated by each member's notification preferences.
  #
  # Idempotent: dedup_key pins a notification to (offer, recipient), so the same
  # offer never alerts twice. A fresh offer row (new sale next week) is a new id,
  # so it alerts again. Matching is substring (same rule the /offers page uses).
  class OfferWatchScanner
    KIND = "offer_match"

    # @param household [Household, nil] defaults to the sole household.
    # @return [Integer] number of notifications newly created this run.
    def self.run(household = Household.current)
      new(household).run
    end

    def initialize(household)
      @household = household
    end

    def run
      return 0 if @household.nil?

      patterns = @household.offer_watchlist_entries.map(&:normalized).compact_blank
      return 0 if patterns.empty?

      @recipients = @household.users.to_a
      return 0 if @recipients.empty?

      matching_offers(patterns).sum { |offer| notify(offer) }
    end

    private

    # Current (in-date) offers whose title contains any watched pattern. Matched
    # in Ruby because the patterns are free-text substrings, not indexable terms.
    def matching_offers(patterns)
      @household.offers.current.to_a.select do |offer|
        OfferWatchlistEntry.match?(patterns, offer.title)
      end
    end

    def notify(offer)
      price = ActiveSupport::NumberHelper.number_to_currency(offer.price)

      @recipients.count do |user|
        next false unless user.notification_preference.allows?(KIND)

        Notification.deliver(
          dedup_key:  "#{KIND}:#{offer.id}:#{user.id}",
          household:  @household,
          user:       user,
          notifiable: offer,
          kind:       KIND,
          title:      I18n.t("notification.offer_match.title"),
          body:       I18n.t("notification.offer_match.body",
                             title: offer.title, price: price, retailer: offer.retailer_name),
          url:        "/offers"
        ).previously_new_record?
      end
    end
  end
end
