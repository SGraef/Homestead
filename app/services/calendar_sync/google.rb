# frozen_string_literal: true
# typed: false

module CalendarSync
  module Google
    # Raised for any Google OAuth / Calendar API failure.
    class Error < StandardError; end

    # A 410 from events.list means the stored syncToken expired -> full re-sync.
    class InvalidSyncToken < Error; end

    # A 412 (If-Match etag mismatch) on update/delete -> conflict, remote wins.
    class Conflict < Error; end
  end
end
