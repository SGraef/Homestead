# frozen_string_literal: true
# typed: false

module CalendarSync
  module Google
    # Raised for any Google OAuth / Calendar API failure.
    class Error < StandardError; end
  end
end
