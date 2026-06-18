# frozen_string_literal: true
# typed: false

# Daily scan that notifies household members about storage items expiring soon
# or just expired. Scoped to the sole household ({Household.current}); a no-op
# when there is none. Wired in config/recurring.yml.
class ScanExpiryRemindersJob < ApplicationJob
  queue_as :default

  def perform
    created = Reminders::ExpiryScanner.run
    Rails.logger.info("[reminders] expiry scan created #{created} notification(s)") if created.positive?
    created
  end
end
