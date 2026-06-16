# frozen_string_literal: true
# typed: false

module CalendarSync
  module Google
    # Authenticated Google Calendar API v3 client (Net::HTTP/JSON), refreshing
    # the access token on demand. Maps 410 -> InvalidSyncToken and 412 -> Conflict
    # so callers can react (full re-sync / remote-wins).
    class ApiClient
      BASE = "https://www.googleapis.com/calendar/v3"

      def initialize(connection)
        @connection = connection
      end

      def list_calendars
        get("/users/me/calendarList").fetch("items", [])
      end

      # One page of changes; incremental with a syncToken, bounded backfill
      # without one. Raises InvalidSyncToken on 410.
      def list_events(calendar_id, sync_token: nil, page_token: nil)
        params = { singleEvents: "true", showDeleted: "true", maxResults: "250" }
        if sync_token.present?
          params[:syncToken] = sync_token
        else
          params[:timeMin] = 90.days.ago.utc.iso8601
        end
        params[:pageToken] = page_token if page_token.present?
        get("/calendars/#{CGI.escape(calendar_id)}/events", params)
      end

      def get_event(calendar_id, event_id)
        get("/calendars/#{CGI.escape(calendar_id)}/events/#{CGI.escape(event_id)}")
      end

      # @return [Hash] the created event (id, etag, ...)
      def insert_event(calendar_id, body)
        send_json(Net::HTTP::Post, "/calendars/#{CGI.escape(calendar_id)}/events", body: body)
      end

      # Conditional update; raises Conflict on 412 (etag mismatch).
      def update_event(calendar_id, event_id, body, etag)
        send_json(Net::HTTP::Put, "/calendars/#{CGI.escape(calendar_id)}/events/#{CGI.escape(event_id)}",
                  body: body, if_match: etag)
      end

      # Conditional delete; 404/410 (already gone) is treated as success.
      def delete_event(calendar_id, event_id, etag)
        response = perform(build(Net::HTTP::Delete,
                                 "/calendars/#{CGI.escape(calendar_id)}/events/#{CGI.escape(event_id)}",
                                 if_match: etag))
        return if [404, 410].include?(response.code.to_i)
        raise Conflict if response.code.to_i == 412
        raise Error, "delete returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      end

      private

      def get(path, params = {})
        uri = URI("#{BASE}#{path}")
        uri.query = params.to_query if params.any?
        parse(perform(authorize(Net::HTTP::Get.new(uri))))
      end

      def send_json(klass, path, body:, if_match: nil)
        parse(perform(build(klass, path, body: body, if_match: if_match)))
      end

      def build(klass, path, body: nil, if_match: nil)
        request = klass.new(URI("#{BASE}#{path}"))
        if body
          request["Content-Type"] = "application/json"
          request.body = body.to_json
        end
        request["If-Match"] = if_match if if_match.present?
        request
      end

      def authorize(request)
        request["Authorization"] = "Bearer #{@connection.access_token}"
        request
      end

      def perform(request)
        ensure_fresh_token!
        authorize(request)
        uri = request.uri
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.request(request)
      end

      def parse(response)
        raise InvalidSyncToken if response.code.to_i == 410
        raise Conflict        if response.code.to_i == 412
        raise Error, "calendar API returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body.present? ? JSON.parse(response.body) : {}
      end

      def ensure_fresh_token!
        Oauth.refresh!(@connection) if @connection.token_expired?
      end
    end
  end
end
