# frozen_string_literal: true
# typed: false

module Reminders
  # Turns storage-item `expires_on` dates into in-app + push notifications for
  # every household member. The first signal of the proactive-reminders engine:
  # it reuses the existing {Notification} ledger (bell + {DeliverPushJob}) rather
  # than introducing a new transport.
  #
  # Two windows, each its own notification kind:
  #
  #   * `storage_expiring` — best-before is today .. +SOON_DAYS (a heads-up).
  #   * `storage_expired`  — best-before fell in the last GRACE_DAYS (use-it-up).
  #
  # Idempotent: the dedup_key pins each notification to (kind, item, date,
  # recipient), so the daily scan never produces a second row for the same
  # item/date — but moving an item's expiry date legitimately re-notifies.
  # Items expired longer ago than GRACE_DAYS stop nagging.
  class ExpiryScanner
    # Heads-up horizon for not-yet-expired items (inclusive of today).
    SOON_DAYS = ENV.fetch("EXPIRY_REMINDER_DAYS", "3").to_i
    # How many days after expiry we keep surfacing an item before going quiet.
    GRACE_DAYS = ENV.fetch("EXPIRY_REMINDER_GRACE_DAYS", "7").to_i

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

      @recipients = @household.users.to_a
      return 0 if @recipients.empty?

      created = 0
      expiring_soon.find_each { |item| created += notify(item, kind: "storage_expiring") }
      recently_expired.find_each { |item| created += notify(item, kind: "storage_expired") }
      created
    end

    private

    # today .. today+SOON_DAYS (inclusive both ends).
    def expiring_soon
      @household.storage_items
                .where(expires_on: Date.current..(Date.current + SOON_DAYS.days))
                .includes(:product)
    end

    # today-GRACE_DAYS .. yesterday (excludes today, which counts as "expiring").
    def recently_expired
      @household.storage_items
                .where(expires_on: (Date.current - GRACE_DAYS.days)...Date.current)
                .includes(:product)
    end

    # Deliver one notification per recipient; returns how many were freshly made.
    def notify(item, kind:)
      name = item.product&.name.presence || I18n.t("notification.storage_expiring.fallback_name")
      date = I18n.l(item.expires_on)

      @recipients.count do |user|
        notification = Notification.deliver(
          dedup_key:  "#{kind}:#{item.id}:#{item.expires_on}:#{user.id}",
          household:  @household,
          user:       user,
          notifiable: item,
          kind:       kind,
          title:      I18n.t("notification.#{kind}.title"),
          body:       I18n.t("notification.#{kind}.body", name: name, date: date),
          url:        "/storage_items/#{item.id}"
        )
        notification.previously_new_record?
      end
    end
  end
end
