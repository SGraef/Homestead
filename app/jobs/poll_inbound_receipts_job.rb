# frozen_string_literal: true
# typed: false

# Drains inbound mailboxes into Receipt rows.
#
# Two callers:
# * config/recurring.yml fires this every 5 minutes with no args -> all
#   configured sources are drained.
# * Api::V1::InboundEmailsController#poll enqueues this with
#   `source_id:` when called with `X-Async: 1` -> only that one source.
class PollInboundReceiptsJob < ApplicationJob
  queue_as :default

  # Don't retry IMAP failures inside a job -- the next scheduled run is
  # the natural retry, and back-pressuring with retry_on would just
  # stack jobs while the IMAP server is unreachable.
  discard_on ActiveJob::DeserializationError

  # @param source_id [Integer, nil] when given, drain only that one
  #   InboundEmailSource; otherwise drain all of them.
  def perform(source_id: nil)
    poller = InboundReceipts::ImapPoller.new
    result =
      if source_id
        source = InboundEmailSource.find_by(id: source_id)
        return unless source

        poller.call_for([source])
      else
        poller.call
      end

    return if result.nil?
    if result.created.positive? || result.errors.positive?
      Rails.logger.info("[InboundReceipts] #{result}")
    end
    result
  end
end
