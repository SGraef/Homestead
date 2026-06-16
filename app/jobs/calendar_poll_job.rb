# frozen_string_literal: true
# typed: false

# Recurring poll (config/recurring.yml, every 5 min) that pulls remote calendar
# changes for the single household's connection. No-op unless connected.
class CalendarPollJob < ApplicationJob
  queue_as :default

  def perform
    connection = Household.current&.calendar_connection
    return unless connection&.connected? && connection.calendar_id.present?

    CalendarSync::Pull.new(connection).call
  end
end
