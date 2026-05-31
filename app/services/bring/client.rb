# frozen_string_literal: true
# typed: false

require "net/http"
require "uri"
require "json"

# Thin REST client for the (private) Bring! API used by their mobile/web app.
# Endpoints documented from community reverse engineering -- there is no
# public OAuth flow.
#
# Auth shape:
#   POST /v2/bringauth                    email + password   -> access_token, refresh_token, uuid, bringListUUID
#   GET  /v2/bringusers/{uuid}/lists      (auth)             -> { lists: [{ listUuid, name }, ...] }
#   GET  /v2/bringlists/{listUuid}        (auth)             -> { purchase: [...], recently: [...] }
#   PUT  /v2/bringlists/{listUuid}        purchase=Milk      -> add an item
#                                         recently=Milk      -> remove an item (moves to "recent")
#
# There is no documented refresh endpoint -- when an access token actually
# expires the user re-authenticates via the connect form.
module Bring
  # Error / AuthError classes live in their own files (bring/error.rb,
  # bring/auth_error.rb) so Zeitwerk's eager_load can resolve them by
  # path. Don't redefine here.
  class Client
    BASE_URL      = "https://api.getbring.com/rest/v2"
    # Public client API key shipped with Bring's first-party clients. Override
    # via env if Bring rotates it.
    API_KEY       = ENV.fetch("BRING_API_KEY",
                              "cof4Nc6D8saplXjE3h3HXqHH8m7VU2i1Gs0g85Sk")
    CLIENT_SOURCE = ENV.fetch("BRING_CLIENT_SOURCE", "webApp")
    CLIENT_VERSION = ENV.fetch("BRING_CLIENT_VERSION", "303070050")
    # Bring's edge has been observed to reject "non-canonical" User-Agent
    # values. Default to a UA that matches the format of the real first-party
    # clients; override via env if Bring tightens it further.
    USER_AGENT    = ENV.fetch("BRING_USER_AGENT", "BringApp/#{CLIENT_VERSION}")
    OPEN_TIMEOUT  = 5
    READ_TIMEOUT  = 8

    # @param connection [BringConnection]
    def initialize(connection)
      @connection = connection
    end

    # Exchange email+password for tokens. Stateless -- does NOT touch the DB.
    # @return [Hash] raw Bring! auth response (`access_token`, `refresh_token`,
    #   `token_type`, `expires_in`, `uuid`, `bringListUUID`, `email`, …)
    def self.login(email:, password:, country: "DE")
      resp = http_request(:post, "/bringauth",
                          headers: base_headers(country: country, content_type: :form),
                          body:    URI.encode_www_form(email: email, password: password))
      raise AuthError, "HTTP #{resp.code}: #{resp.body.to_s.first(300)}" unless resp.is_a?(Net::HTTPSuccess)

      data = JSON.parse(resp.body)
      Rails.logger.info(
        "[Bring] login OK — fields: #{data.keys.inspect}, " \
        "access_token=#{data["access_token"]&.length}chars, " \
        "uuid=#{data["uuid"]}, bringListUUID=#{data["bringListUUID"]}, " \
        "token_type=#{data["token_type"]}, expires_in=#{data["expires_in"]}"
      )
      data
    end

    # @return [Array<Hash>] e.g. `[{ "listUuid" => "...", "name" => "Wohnung" }]`
    def lists
      data = JSON.parse(authenticated(:get, "/bringusers/#{@connection.bring_user_uuid}/lists").body)
      data["lists"] || []
    end

    # @return [Hash] the bound list with `purchase` + `recently` arrays.
    def fetch_list
      JSON.parse(authenticated(:get, "/bringlists/#{@connection.default_list_uuid}").body)
    end

    def push_item(name:, specification: nil)
      authenticated(:put, "/bringlists/#{@connection.default_list_uuid}",
                    headers: { "Content-Type" => "application/x-www-form-urlencoded" },
                    body:    URI.encode_www_form(purchase: name, specification: specification.to_s))
    end

    def remove_item(name:)
      authenticated(:put, "/bringlists/#{@connection.default_list_uuid}",
                    headers: { "Content-Type" => "application/x-www-form-urlencoded" },
                    body:    URI.encode_www_form(recently: name))
    end

    private

    # No retries / refresh dance: Bring! has no documented refresh endpoint,
    # so the simplest correct behavior is "use the token, surface real errors,
    # don't ever silently scrub the connection". When the token has actually
    # expired (1h+ for typical Bring deployments) the user re-runs the
    # connect form.
    def authenticated(method, path, headers: {}, body: nil)
      raise AuthError, "Not connected to Bring" if @connection.access_token.blank?

      sent_headers = auth_headers.merge(headers)
      resp = self.class.http_request(method, path, headers: sent_headers, body: body)
      return resp if resp.is_a?(Net::HTTPSuccess)

      body_excerpt = resp.body.to_s.strip.first(500)
      log_failure(method, path, sent_headers, resp, body_excerpt)

      if resp.code == "401"
        # Don't scrub the access token -- a single 401 might just be Bring
        # tightening header validation, not the token actually being invalid.
        # The user can retry / reconnect; we just record what happened.
        @connection.update_columns(
          last_error: "Bring rejected the token (HTTP 401). #{body_excerpt}".first(500),
          updated_at: Time.current
        )
        raise AuthError, "Bring rejected the token (HTTP 401): #{body_excerpt}"
      end

      raise Error, "Bring API #{method.upcase} #{path} failed: HTTP #{resp.code}: #{body_excerpt}"
    end

    def log_failure(method, path, sent_headers, resp, body_excerpt)
      redacted = sent_headers.transform_values do |v|
        case v
        when /\A(Bearer|JWT|Basic) (.+)/i
          "#{::Regexp.last_match(1)} <redacted:#{::Regexp.last_match(2).length}chars>"
        else v
        end
      end
      Rails.logger.warn(
        "[Bring] #{method.upcase} #{path} failed: HTTP #{resp.code}\n  " \
        "Response: #{body_excerpt}\n  " \
        "Sent headers: #{redacted.inspect}"
      )
    end

    def auth_headers
      token_type = @connection.respond_to?(:token_type) ? (@connection.token_type.presence || "Bearer") : "Bearer"
      self.class.base_headers(country: @connection.country_code).merge(
        "Authorization"     => "#{token_type} #{@connection.access_token}",
        "X-BRING-USER-UUID" => @connection.bring_user_uuid
      )
    end

    # ---- HTTP --------------------------------------------------------------

    def self.http_request(method, path, headers: {}, body: nil)
      uri  = URI("#{BASE_URL}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      req_class = case method
                  when :get  then Net::HTTP::Get
                  when :post then Net::HTTP::Post
                  when :put  then Net::HTTP::Put
                  end
      req = req_class.new(uri.request_uri, headers)
      req.body = body if body
      http.request(req)
    end

    def self.base_headers(country:, content_type: nil)
      country = country.to_s.upcase
      # Mirrors the canonical header set used by reverse-engineered Bring
      # libraries (e.g. miaucl/bring-api). Keep this minimal -- adding extra
      # headers like Accept-Language has been observed to trigger 401s on
      # some Bring edges.
      h = {
        "X-BRING-API-KEY"       => API_KEY,
        "X-BRING-CLIENT"        => CLIENT_SOURCE,
        "X-BRING-CLIENT-SOURCE" => CLIENT_SOURCE,
        "X-BRING-COUNTRY"       => country,
        "X-BRING-VERSION"       => CLIENT_VERSION,
        "User-Agent"            => USER_AGENT,
        "Accept"                => "application/json"
      }
      # Only set Content-Type when there's actually a body. A stray
      # `Content-Type: application/json` on a GET has been seen to trip
      # Bring's edge into a 401.
      case content_type
      when :form then h["Content-Type"] = "application/x-www-form-urlencoded"
      when :json then h["Content-Type"] = "application/json"
      end
      h
    end

    private_class_method :http_request, :base_headers
  end
end
