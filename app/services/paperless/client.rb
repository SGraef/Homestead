# frozen_string_literal: true
# typed: false

require "net/http"
require "uri"
require "json"
require "securerandom"

module Paperless
  # Minimal REST client for a self-hosted paperless-ngx instance, scoped to one
  # {PaperlessConnection}. Covers exactly what Homestead needs:
  #
  #   * ping            — verify base URL + token (the "Test connection" button)
  #   * upload          — POST a file; paperless consumes it asynchronously and
  #                       returns a Celery task UUID
  #   * task            — poll that UUID until the document is consumed
  #   * document        — read the consumed document (type / correspondent / tag
  #                       *ids*)
  #   * type/correspondent/tag — resolve those ids to human names
  #
  # SSRF note: paperless almost always lives on a private LAN address
  # (192.168.x, *.home.lan, ...), which {SafeHttp}'s guard deliberately blocks
  # for *untrusted* fetches. Here the base URL is admin-entered and trusted --
  # reaching an internal host is the entire point -- so we validate the scheme
  # ourselves and skip the private-range block. `verify_ssl` lets a household
  # accept the self-signed cert that internal deployments often run.
  class Client
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30
    MAX_REDIRECTS = 5
    ALLOWED_SCHEMES = %w[http https].freeze

    # @param connection [PaperlessConnection]
    def initialize(connection)
      @connection = connection
    end

    # Verify the base URL + token reach a paperless API. We hit a concrete,
    # auth-required JSON endpoint rather than the bare `/api/` root: some
    # paperless versions 302 `/api/` to the HTML Swagger view (which 406s a
    # JSON Accept), whereas `/api/ui_settings/` returns JSON on every version
    # and also validates the token. Returns the parsed body; raises on failure.
    # @return [Hash] the paperless ui_settings document
    # @raise [Paperless::AuthError, Paperless::Error]
    def ping
      get_json("/api/ui_settings/")
    end

    # Upload a file. paperless consumes it asynchronously.
    # @param io [IO] the file contents
    # @param filename [String]
    # @param title [String, nil]
    # @param tags [Array<String>] tag *names*; paperless creates missing ones
    # @return [String] the Celery task UUID to poll via {#task}
    def upload(io:, filename:, title: nil, tags: [])
      parts = []
      parts << file_part("document", filename, io.read)
      parts << field_part("title", title) if title.present?
      Array(tags).each { |t| parts << field_part("tags", t) }

      boundary = "----HomesteadPaperless#{SecureRandom.hex(12)}"
      body = build_multipart(parts, boundary)
      resp = request(:post, "/api/documents/post_document/",
                     headers: { "Content-Type" => "multipart/form-data; boundary=#{boundary}" },
                     body:    body)
      # The endpoint returns the task UUID as a bare JSON string, e.g.
      #   "6f3b...-..."  (quotes included). Parse, then strip stray quotes.
      JSON.parse(resp.body.to_s)
    rescue JSON::ParserError
      resp.body.to_s.strip.delete('"')
    end

    # @param uuid [String]
    # @return [Hash, nil] the task record (status / related_document / result),
    #   or nil if paperless doesn't know the UUID yet.
    def task(uuid)
      Array(get_json("/api/tasks/?task_id=#{URI.encode_www_form_component(uuid)}")).first
    end

    # @param id [Integer]
    # @return [Hash] the consumed document (type/correspondent/tag *ids*).
    def document(id)
      get_json("/api/documents/#{id}/")
    end

    # @return [String, nil] the name for a document_type / correspondent / tag id.
    def document_type_name(id) = lookup_name("/api/document_types/#{id}/", id)
    def correspondent_name(id) = lookup_name("/api/correspondents/#{id}/", id)
    def tag_name(id)           = lookup_name("/api/tags/#{id}/", id)

    private

    def lookup_name(path, id)
      return nil if id.blank?

      get_json(path)["name"]
    rescue Paperless::Error
      nil
    end

    def get_json(path)
      JSON.parse(request(:get, path).body.to_s)
    end

    def request(method, path, headers: {}, body: nil)
      perform(method, build_uri(path), headers, body, MAX_REDIRECTS)
    rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise Error, "paperless #{method.upcase} #{path} failed: #{e.class}: #{e.message}"
    end

    def perform(method, uri, headers, body, redirects_left)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl? && !@connection.verify_ssl
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      req = request_class(method).new(uri.request_uri, request_headers(headers))
      req.body = body if body
      resp = http.request(req)
      return resp if resp.is_a?(Net::HTTPSuccess)
      # Reverse proxies and http->https upgrades commonly 3xx the API root;
      # follow them (GET only) so the connection still works. POSTs aren't
      # replayed -- re-uploading a document on a redirect could duplicate it.
      if method == :get && resp.is_a?(Net::HTTPRedirection)
        return follow(method, uri, headers, body, resp, redirects_left)
      end

      raise_for(resp, method, uri.request_uri)
    end

    # Follow a redirect, but only to the SAME host -- the Authorization: Token
    # header rides along, so we must not leak it to a host the redirect points
    # at. A cross-host (or schemeless) redirect surfaces the Location so the
    # user can correct the base URL.
    def follow(method, uri, headers, body, resp, redirects_left)
      location = resp["location"].to_s
      target = (URI.join(uri.to_s, location) if location.present?)
      raise Error, redirect_message(uri, location, resp) if redirects_left <= 0 || !same_host_http?(uri, target)

      perform(method, target, headers, body, redirects_left - 1)
    end

    def same_host_http?(uri, target)
      target.is_a?(URI::HTTP) && ALLOWED_SCHEMES.include?(target.scheme) && target.host&.casecmp?(uri.host)
    end

    def redirect_message(uri, location, resp)
      "paperless redirected GET #{uri.request_uri} to #{location.presence || "(no Location header)"} " \
        "(HTTP #{resp.code}) -- check the base URL: right scheme (http vs https), host and port?"
    end

    def raise_for(resp, method, path)
      excerpt = resp.body.to_s.strip.first(300)
      raise AuthError, "paperless rejected the token (HTTP #{resp.code}): #{excerpt}" if %w[401 403].include?(resp.code)

      raise Error, "paperless #{method.upcase} #{path} failed: HTTP #{resp.code}: #{excerpt}"
    end

    def build_uri(path)
      uri = URI.parse("#{@connection.normalized_base_url}#{path}")
      unless uri.is_a?(URI::HTTP) && ALLOWED_SCHEMES.include?(uri.scheme) && uri.host.present?
        raise Error, "invalid paperless URL: #{uri}"
      end

      uri
    end

    def request_class(method)
      { get: Net::HTTP::Get, post: Net::HTTP::Post }.fetch(method)
    end

    def request_headers(extra)
      { "Authorization" => "Token #{@connection.api_token}", "Accept" => "application/json" }.merge(extra)
    end

    def field_part(name, value)
      "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}"
    end

    def file_part(name, filename, content)
      "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{filename}\"\r\n" \
        "Content-Type: application/octet-stream\r\n\r\n#{content}"
    end

    def build_multipart(parts, boundary)
      "--#{boundary}\r\n" + parts.join("\r\n--#{boundary}\r\n") + "\r\n--#{boundary}--\r\n"
    end
  end
end
