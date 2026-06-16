# frozen_string_literal: true
# typed: false

# Pushes one local CalendarEvent change to the remote calendar. Delete carries
# the remote anchors explicitly because the local row is already gone.
class CalendarPushJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(action, event_id: nil, connection_id: nil, calendar_id: nil, remote_id: nil, etag: nil)
    case action.to_s
    when "create", "update"
      event = CalendarEvent.find_by(id: event_id)
      return unless event&.pushable?

      CalendarSync::Push.new(event).public_send(action)
    when "delete"
      connection = CalendarConnection.find_by(id: connection_id)
      return unless connection&.connected? && calendar_id.present? && remote_id.present?

      CalendarSync::Google::ApiClient.new(connection).delete_event(calendar_id, remote_id, etag)
    end
  rescue CalendarSync::Google::Error => e
    Rails.logger.warn("[calendar push] #{action} failed: #{e.class}")
  end
end
