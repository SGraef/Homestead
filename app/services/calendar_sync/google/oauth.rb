# frozen_string_literal: true
# typed: false

module CalendarSync
  module Google
    # Google OAuth 2.0 authorization-code flow + refresh. The operator supplies
    # the client_id/secret (stored encrypted on the CalendarConnection); we never
    # ship a shared client. access_type=offline + prompt=consent so we always get
    # a refresh_token on first connect.
    module Oauth
      AUTH_URI  = "https://accounts.google.com/o/oauth2/v2/auth"
      TOKEN_URI = "https://oauth2.googleapis.com/token"
      SCOPE     = "https://www.googleapis.com/auth/calendar"

      module_function

      # @return [String] the Google consent URL to redirect the admin to.
      def authorize_url(connection, redirect_uri:, state:)
        query = {
          client_id:              connection.client_id,
          redirect_uri:           redirect_uri,
          response_type:          "code",
          scope:                  SCOPE,
          access_type:            "offline",
          include_granted_scopes: "true",
          prompt:                 "consent",
          state:                  state
        }.to_query
        "#{AUTH_URI}?#{query}"
      end

      # Exchange the authorization code for tokens and mark the connection connected.
      def exchange_code(connection, code:, redirect_uri:)
        body = post_token(
          client_id:     connection.client_id,
          client_secret: connection.client_secret,
          code:          code,
          grant_type:    "authorization_code",
          redirect_uri:  redirect_uri
        )
        connection.update!(
          access_token:     body["access_token"],
          refresh_token:    body["refresh_token"].presence || connection.refresh_token,
          token_expires_at: Time.current + body.fetch("expires_in", 3600).to_i.seconds,
          status:           "connected",
          last_error_code:  nil
        )
      end

      # Refresh the access token using the stored refresh_token.
      def refresh!(connection)
        raise Error, "no refresh token" if connection.refresh_token.blank?

        body = post_token(
          client_id:     connection.client_id,
          client_secret: connection.client_secret,
          refresh_token: connection.refresh_token,
          grant_type:    "refresh_token"
        )
        connection.update!(
          access_token:     body["access_token"],
          token_expires_at: Time.current + body.fetch("expires_in", 3600).to_i.seconds
        )
      end

      def post_token(form)
        uri = URI(TOKEN_URI)
        SafeHttp.validate_uri!(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(form)
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "token endpoint returned #{response.code}"
        end

        JSON.parse(response.body)
      end
    end
  end
end
