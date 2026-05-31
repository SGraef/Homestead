# frozen_string_literal: true
# typed: false

require "net/http"
require "json"
require "uri"

module Marktguru
  # Adapter around Marktguru's offer API. ⚠️ Reverse-engineered from the
  # marktguru.de web client (see config block embedded in the homepage's
  # `<script type="application/json">`). Endpoints, headers, and response
  # shapes can change without notice -- we parse defensively, swallow
  # errors, log, and return [] on anything weird.
  #
  # Real flow (validated 2026-05):
  #
  #   * Host: api.marktguru.de (NOT www.marktguru.de)
  #   * Required: `X-ApiKey: <bootstrap_key>` header — published in the
  #     marktguru.de homepage as `config.apiKey`. Refetch from there if
  #     it gets rotated; or override via MARKTGURU_API_KEY env var.
  #   * Offers are *industry-scoped*: there is no global `/offers` feed.
  #     Each industry (Supermarkt, Discounter, Drogerie, …) has its own
  #     list at `/api/v1/industries/<uniqueName>/offers?as=mobile&zipCode=…`.
  #
  # Response shape:
  #
  #   { "totalResults": 802, "skippedResults": 0,
  #     "results": [
  #       { "id": 22837988,
  #         "description": "je 250-g-Pckg./ Becher",
  #         "product":  { "id": 20742, "name": "Butter" },
  #         "retailer": { "id": 126802, "name": "REWE",  "uniqueName": "rewe" },
  #         "brand":    { "id": 124811, "name": "Weihenstephan",
  #                       "uniqueName": "weihenstephan" },
  #         "price": 1.19, "oldPrice": 0.0,
  #         "validFrom": "2026-05-03T22:00:00Z",
  #         "validTo":   "2026-05-09T21:59:00Z" } ] }
  class Offers
    HOST           = "api.marktguru.de"
    OFFER_PAGE_URL = "https://www.marktguru.de/angebote/%s"
    OPEN_TIMEOUT   = 6
    READ_TIMEOUT   = 12
    USER_AGENT     = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:124.0) " \
                     "Gecko/20100101 Firefox/124.0"

    # Bootstrap API key. Override at deploy time if Marktguru rotates it
    # (the same key is publicly readable from their homepage's embedded
    # config block, so we keep the last-known value as a default).
    API_KEY = ENV.fetch("MARKTGURU_API_KEY",
                        "8Kk+pmbf7TgJ9nVj2cXeA7P5zBGv8iuutVVMRfOfvNE=")

    # Industries (uniqueName values) we sweep by default. The full list
    # lives at /api/v1/industries; these three cover groceries +
    # drugstore staples. Override with MARKTGURU_INDUSTRIES env var:
    #   MARKTGURU_INDUSTRIES=supermaerkte,discounter,baumaerkte
    DEFAULT_INDUSTRIES = %w[supermaerkte discounter drogerie-gesundheit].freeze

    OfferData = Struct.new(
      :external_id, :title, :brand, :category,
      :retailer_name, :retailer_slug,
      :price_cents, :regular_price_cents, :currency,
      :unit, :quantity_text, :image_url, :source_url,
      :valid_from, :valid_until,
      keyword_init: true
    )

    class << self
      # Fan out across the configured industries and pull every current
      # offer for the postcode. Dedupes by external_id (different
      # industries occasionally surface the same offer).
      #
      # @param postal_code [String]
      # @param page_size [Integer] limit per industry page
      # @param max_pages [Integer] hard cap per industry
      # @param industries [Array<String>, nil] override slug list
      # @return [Array<OfferData>]
      def pull_all(postal_code:, page_size: 50, max_pages: 10, industries: nil)
        pc = postal_code.to_s.strip
        return [] if pc.empty?

        slugs = industries || ENV["MARKTGURU_INDUSTRIES"]&.split(",")&.map(&:strip)&.compact_blank
        slugs = DEFAULT_INDUSTRIES if slugs.blank?

        seen = {}
        slugs.each do |slug|
          fetch_industry(slug, postal_code: pc,
                                limit: page_size, max_pages: max_pages) do |row|
            built = build(row, industry: slug)
            seen[built.external_id] = built if built
          end
        end
        seen.values
      end

      # @return [Array<Hash>] raw industry list (id, name, uniqueName, …).
      #   Useful when curating MARKTGURU_INDUSTRIES.
      def industries
        data = get_json("https://#{HOST}/api/v1/industries?as=mobile&limit=64")
        Array(data && data["results"])
      end

      # ---- internals -------------------------------------------------------

      # Yields each offer row from one industry's offer feed, paginating.
      def fetch_industry(slug, postal_code:, limit:, max_pages:, &block)
        offset = 0
        max_pages.times do
          params = { as: "mobile", zipCode: postal_code, limit: limit, offset: offset }
          url    = "https://#{HOST}/api/v1/industries/" \
                   "#{URI.encode_www_form_component(slug)}/offers?" \
                   "#{URI.encode_www_form(params)}"
          data   = get_json(url)
          rows   = Array(data && data["results"])
          break if rows.empty?

          rows.each(&block)
          break if rows.size < limit

          offset += limit
        end
      end

      def build(raw, industry: nil)
        return nil unless raw.is_a?(Hash)

        ext_id = raw["id"].to_s
        return nil if ext_id.empty?

        price_cents = to_cents(raw["price"])
        return nil unless price_cents

        title = raw.dig("product", "name").presence || raw["description"].presence
        return nil if title.to_s.strip.empty?

        old_cents = to_cents(raw["oldPrice"])
        OfferData.new(
          external_id:         ext_id,
          title:               title.to_s.strip,
          brand:               raw.dig("brand", "name").presence,
          category:            industry,
          retailer_name:       raw.dig("retailer", "name").to_s.strip.presence ||
                               raw.dig("advertiser", "name").to_s.strip.presence ||
                               "Unknown",
          retailer_slug:       raw.dig("retailer", "uniqueName").presence,
          price_cents:         price_cents,
          regular_price_cents: old_cents&.positive? ? old_cents : nil,
          currency:            "EUR",
          unit:                parse_unit(raw["description"]),
          quantity_text:       raw["description"].presence,
          image_url:           nil, # TODO: derive from media host + product/brand id
          source_url:          format(OFFER_PAGE_URL, ext_id),
          valid_from:          parse_date(raw["validFrom"]),
          valid_until:         parse_date(raw["validTo"])
        )
      end

      def to_cents(value)
        return nil if value.nil?

        BigDecimal(value.to_s).mult(100, 0).round.to_i
      rescue ArgumentError
        nil
      end

      def parse_date(value)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Best-effort {Product::UNITS} guess from a quantity string ("1 L",
      # "500 g", "12 Stk").
      def parse_unit(text)
        return nil if text.to_s.empty?

        case text.downcase
        when /\b(?:l|liter|litre|litres)\b/    then "l"
        when /\bml\b/                          then "ml"
        when /\bkg\b/                          then "kg"
        when /\bg\b/                           then "g"
        when /\b(?:pcs|stk|stück|x)\b/         then "pcs"
        end
      end

      def get_json(url)
        uri  = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        req = Net::HTTP::Get.new(
          uri.request_uri,
          "User-Agent" => USER_AGENT,
          "Accept"     => "application/json",
          "Origin"     => "https://www.marktguru.de",
          "Referer"    => "https://www.marktguru.de/",
          "X-ApiKey"   => API_KEY
        )
        resp = http.request(req)
        return JSON.parse(resp.body) if resp.is_a?(Net::HTTPSuccess)

        Rails.logger.warn("[Marktguru::Offers] HTTP #{resp.code} for #{url}")
        nil
      rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout,
             SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
        Rails.logger.warn("[Marktguru::Offers] #{e.class}: #{e.message} (#{url})")
        nil
      end
    end
  end
end
