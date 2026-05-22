# frozen_string_literal: true
# typed: false

# Recurring job that drains the configured IMAP mailbox into Receipt rows.
# Wired up in config/recurring.yml; no-ops when IMAP isn't configured so
# the schedule can stay enabled in environments that don't use it.
class PollInboundReceiptsJob < ApplicationJob
  queue_as :default

  # Don't retry IMAP failures inside a job -- the next scheduled run is
  # the natural retry, and back-pressuring with retry_on would just
  # stack jobs while the IMAP server is unreachable.
  discard_on ActiveJob::DeserializationError

  def perform
    result = InboundReceipts::ImapPoller.new.call
    return if result.nil? # not configured

    if result.created.positive? || result.errors.positive?
      Rails.logger.info("[InboundReceipts] #{result}")
    end
    result
  end
end
