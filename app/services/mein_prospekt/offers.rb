# frozen_string_literal: true
# typed: true

require "net/http"
require "json"
require "uri"

module MeinProspekt
  # Adapter for meinprospekt.de's public search API. Replaces the
  # earlier OCR-on-PDF pipeline for ALDI Nord — same data source we use
  # for kaufDA (Bonial group), but with a paginated keyword search that
  # cleanly returns ~280 offers per retailer query as structured JSON.
  #
  # No auth, no cookies, no API key — plain HTTP GET against
  # `https://www.meinprospekt.de/api/search?query=…&lat=…&lng=…&offset=…&limit=24`.
  # The endpoint takes a city's lat/lng to scope offers to that region
  # (defaults to Bremen here; override via MEINPROSPEKT_LAT/LNG).
  #
  # `MEINPROSPEKT_QUERIES` is a comma-separated list of publisher names
  # to search for. Each entry results in one full paginated sweep:
  #   MEINPROSPEKT_QUERIES="ALDI Nord,Aldi Süd,Tegut"
  #
  # Useful when a retailer isn't covered by Marktguru or kaufDA's
  # `/Geschaefte/<slug>` retailer pages but is indexed by MeinProspekt's
  # broader search.
  class Offers
    SEARCH_URL = "https://www.meinprospekt.de/api/search"
    USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
    OPEN_TIMEOUT = 6
    READ_TIMEOUT = 15

    # Page size hard-coded by the API; passing >24 still caps at 24.
    PAGE_SIZE  = 24
    # Safety stop. 20 × 24 = 480 offers per query is well above ALDI's
    # typical ~280/week; pathological responses won't run forever.
    MAX_PAGES  = 20

    # Bremen (28195) — the household whose data drove this integration.
    # Adjust via env vars when deploying elsewhere.
    DEFAULT_LAT = 53.07564
    DEFAULT_LNG = 8.80789

    # No validity is shipped on individual offers from this endpoint
    # (they're "search ad placements"; the dates live on the parent
    # brochure, which would need a second call per offer). We pin a
    # conservative one-week valid_until so sweep_expired eventually
    # cleans up rows that the API stops returning -- daily sync
    # refreshes it for offers still in the feed.
    VALIDITY_DAYS = 7

    DEFAULT_QUERIES = ["ALDI Nord"].freeze

    OfferData = Struct.new(
      :external_id, :title, :brand, :category,
      :retailer_name, :retailer_slug,
      :price_cents, :regular_price_cents, :currency,
      :unit, :quantity_text, :image_url, :source_url,
      :valid_from, :valid_until,
      keyword_init: true
    )

    class << self
      # @return [Array<OfferData>]
      def pull_all(queries: nil, lat: nil, lng: nil)
        qs   = queries || ENV["MEINPROSPEKT_QUERIES"]&.split(",")&.map(&:strip)&.compact_blank
        qs   = DEFAULT_QUERIES if qs.blank?
        lat  = (lat || ENV["MEINPROSPEKT_LAT"]&.to_f).presence || DEFAULT_LAT
        lng  = (lng || ENV["MEINPROSPEKT_LNG"]&.to_f).presence || DEFAULT_LNG

        out = {}
        qs.each do |query|
          fetch_query(query, lat: lat, lng: lng) do |raw|
            built = build(raw, query: query)
            out[built.external_id] = built if built
          end
        end
        out.values
      end

      # ---- internals -------------------------------------------------------

      # Paginates one query until either a short page (< PAGE_SIZE) or
      # MAX_PAGES, yielding each offer hash to the block.
      def fetch_query(query, lat:, lng:)
        MAX_PAGES.times do |i|
          offset = i * PAGE_SIZE
          params = { query: query, lat: lat, lng: lng,
                     offset: offset, limit: PAGE_SIZE }
          url    = "#{SEARCH_URL}?#{URI.encode_www_form(params)}"

          data = get_json(url)
          offers = Array(data&.dig("searchResults", "contents", "offers"))
          break if offers.empty?

          offers.each { |o| yield o }
          break if offers.size < PAGE_SIZE
        end
      end

      def build(raw, query:)
        return nil unless raw.is_a?(Hash)

        ext_id = raw["id"].to_s
        return nil if ext_id.empty?

        title = raw["title"].to_s.strip
        return nil if title.empty?

        price_cents = to_cents(raw.dig("prices", "mainPrice"))
        return nil unless price_cents

        secondary   = to_cents(raw.dig("prices", "secondaryPrice"))
        regular_cts = (secondary && secondary > price_cents) ? secondary : nil

        OfferData.new(
          external_id:         ext_id,
          title:               title,
          brand:               raw["brand"].to_s.presence,
          category:            nil,
          retailer_name:       raw["publisherName"].to_s.presence || query,
          retailer_slug:       (raw["publisherId"] || query).to_s.downcase.tr(" ", "-"),
          price_cents:         price_cents,
          regular_price_cents: regular_cts,
          currency:            "EUR",
          unit:                nil,
          quantity_text:       raw.dig("prices", "priceByBaseUnit").to_s.presence,
          image_url:           raw.dig("offerImages", "url", "normal").presence ||
                               raw.dig("offerImages", "url", "thumbnail").presence,
          source_url:          search_page_url(query),
          valid_from:          Date.current,
          valid_until:         Date.current + VALIDITY_DAYS
        )
      end

      def search_page_url(query)
        "https://www.meinprospekt.de/search?#{URI.encode_www_form(query: query)}"
      end

      def to_cents(value)
        return nil if value.nil?

        BigDecimal(value.to_s).mult(100, 0).round.to_i
      rescue ArgumentError
        nil
      end

      def get_json(url)
        uri  = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        req = Net::HTTP::Get.new(
          uri.request_uri,
          "User-Agent"      => USER_AGENT,
          "Accept"          => "*/*",
          "Accept-Language" => "de-DE,de;q=0.9",
          "Referer"         => "https://www.meinprospekt.de/"
        )
        resp = http.request(req)
        return JSON.parse(resp.body) if resp.is_a?(Net::HTTPSuccess)

        Rails.logger.warn("[MeinProspekt::Offers] HTTP #{resp.code} for #{url}")
        nil
      rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout,
             SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
        Rails.logger.warn("[MeinProspekt::Offers] #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
