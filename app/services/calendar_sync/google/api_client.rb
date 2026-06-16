# frozen_string_literal: true
# typed: false

module CalendarSync
  module Google
    # Thin authenticated Google Calendar API v3 client. Refreshes the access
    # token on demand. PR2 uses only calendar discovery; event sync (events.list
    # / insert / update / delete) is added in later PRs.
    class ApiClient
      BASE = "https://www.googleapis.com/calendar/v3"

      def initialize(connection)
        @connection = connection
      end

      # @return [Array<Hash>] the user's calendars (id, summary, primary, accessRole).
      def list_calendars
        get("/users/me/calendarList").fetch("items", [])
      end

      private

      def get(path, params = {})
        ensure_fresh_token!
        uri = URI("#{BASE}#{path}")
        uri.query = params.to_query if params.any?

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@connection.access_token}"

        response = http.request(request)
        raise Error, "calendar API returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      def ensure_fresh_token!
        Oauth.refresh!(@connection) if @connection.token_expired?
      end
    end
  end
end
