# frozen_string_literal: true
# typed: false

module CalendarSync
  module Google
    # Maps a Google Calendar API event (singleEvents=true) to CalendarEvent
    # attributes and back. Must run inside Time.use_zone(household.timezone) so
    # all-day DATE values resolve to local midnight (stored UTC).
    module EventMapper
      module_function

      # @param item [Hash] a Google event resource
      # @return [Hash] attributes for a CalendarEvent (sync_origin: "remote")
      def to_attributes(item)
        all_day = item.dig("start", "date").present?
        {
          title:       item["summary"].presence || "(kein Titel)",
          starts_at:   parse_point(item["start"]),
          ends_at:     parse_point(item["end"]),
          all_day:     all_day,
          recurring:   item["recurringEventId"].present?,
          remote_id:   item["id"],
          etag:        item["etag"],
          sync_origin: "remote"
        }
      end

      # @param event [CalendarEvent]
      # @return [Hash] a Google event body for insert/update. Call inside
      #   Time.use_zone(household.timezone) so all-day dates use the local day.
      def to_google(event)
        finish = event.ends_at || event.starts_at
        if event.all_day
          {
            summary: event.title,
            start:   { date: event.starts_at.in_time_zone.to_date.iso8601 },
            end:     { date: finish.in_time_zone.to_date.iso8601 }
          }
        else
          {
            summary: event.title,
            start:   { dateTime: event.starts_at.utc.iso8601 },
            end:     { dateTime: finish.utc.iso8601 }
          }
        end
      end

      # @return [Time, nil]
      def parse_point(point)
        return nil if point.nil?

        if (date = point["date"])
          Date.parse(date).in_time_zone.beginning_of_day # Time.zone = household tz
        else
          Time.zone.parse(point["dateTime"]) # offset-aware -> absolute instant
        end
      end
    end
  end
end
