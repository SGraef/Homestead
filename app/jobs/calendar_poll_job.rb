# frozen_string_literal: true
# typed: false

# Recurring poll (config/recurring.yml, every 5 min) that pulls remote calendar
# changes for the single household's connection. No-op unless connected.
class CalendarPollJob < ApplicationJob
  queue_as :default
  # Only one poll at a time — overlapping full syncs race on the
  # (connection, remote_id) unique index. Later polls wait, then run incremental.
  limits_concurrency to: 1, key: ->(*) { "calendar-poll" }, duration: 15.minutes

  def perform
    connection = Household.current&.calendar_connection
    return unless connection&.connected? && connection.calendar_id.present?

    CalendarSync::Pull.new(connection).call
  end
end
