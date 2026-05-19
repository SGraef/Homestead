# frozen_string_literal: true
# typed: true

require "net/http"
require "json"
require "uri"

module Kaufda
  # Adapter for kaufDA / Bonial's retailer-listing pages. Each retailer has
  # a public SSR Next.js page at
  #
  #   https://www.kaufda.de/Geschaefte/<RetailerSlug>
  #
  # whose `__NEXT_DATA__` carries the full offer feed for that retailer
  # (already structured: title, brand, price, validity, image URLs). No
  # API key, no session cookie -- just GET + parse the embedded JSON.
  #
  # ⚠️ Reverse-engineered, will break if Bonial moves the data shape.
  # Defensive parsing + per-retailer error swallowing means a broken
  # adapter degrades to "no extra offers" rather than breaking the sync.
  #
  # Default coverage: ALDI Nord (the gap that motivated this integration).
  # Add more via the `KAUFDA_RETAILERS` env var, comma-separated:
  #
  #   KAUFDA_RETAILERS=Aldi-Nord,Aldi-Sued,Action
  class Offers
    BASE_URL          = "https://www.kaufda.de"
    PAGE_URL_TEMPLATE = "#{BASE_URL}/Geschaefte/%s"
    OPEN_TIMEOUT      = 6
    READ_TIMEOUT      = 12
    USER_AGENT        = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:124.0) " \
                        "Gecko/20100101 Firefox/124.0"

    DEFAULT_RETAILERS = %w[Aldi-Nord].freeze

    # Same shape as Marktguru::Offers::OfferData so OfferSyncer can treat
    # both interchangeably. (Duck-typing across two adapters is cheap; if
    # we ever grow a third source we'll factor a shared module.)
    OfferData = Struct.new(
      :external_id, :title, :brand, :category,
      :retailer_name, :retailer_slug,
      :price_cents, :regular_price_cents, :currency,
      :unit, :quantity_text, :image_url, :source_url,
      :valid_from, :valid_until,
      keyword_init: true
    )

    class << self
      # @param postal_code [String, nil] accepted for interface symmetry
      #   with Marktguru::Offers; kaufDA's /Geschaefte pages aren't
      #   localized at the URL level, so we ignore it.
      # @param retailers [Array<String>, nil] override default slug list
      # @return [Array<OfferData>]
      def pull_all(postal_code: nil, retailers: nil)
        slugs = retailers ||
                ENV["KAUFDA_RETAILERS"]&.split(",")&.map(&:strip)&.compact_blank
        slugs = DEFAULT_RETAILERS if slugs.blank?

        seen = {}
        slugs.each do |slug|
          fetch_retailer(slug).each do |data|
            seen[data.external_id] = data
          end
        end
        seen.values
      end

      # ---- internals -------------------------------------------------------

      # @return [Array<OfferData>]
      def fetch_retailer(slug)
        url  = format(PAGE_URL_TEMPLATE, slug)
        html = http_get(url)
        return [] unless html

        m = html.match(%r{<script[^>]*id="__NEXT_DATA__"[^>]*>(.+?)</script>}m)
        return [] unless m

        data  = JSON.parse(m[1])
        items = data.dig("props", "pageProps", "pageInformation", "offers", "main", "items") || []
        items.filter_map { |o| build(o, slug) }
      rescue JSON::ParserError => e
        Rails.logger.warn("[KaufDA::Offers] JSON parse failed for #{slug}: #{e.message}")
        []
      end

      def build(raw, slug)
        return nil unless raw.is_a?(Hash)

        ext_id = raw["id"].to_s
        return nil if ext_id.empty?

        title = raw["title"].to_s.strip
        return nil if title.empty?

        price_cents = to_cents(raw.dig("prices", "mainPrice"))
        return nil unless price_cents

        # secondaryPrice doubles as the "Strike-through" price (regular
        # price or UVP). Only treat it as a regular price when it's
        # actually higher than the sale.
        secondary    = to_cents(raw.dig("prices", "secondaryPrice"))
        regular_cts  = (secondary && secondary > price_cents) ? secondary : nil

        OfferData.new(
          external_id:         ext_id,
          title:               title,
          brand:               raw["brand"].presence,
          category:            nil,
          retailer_name:       raw["publisherName"].to_s.presence || slug.tr("-", " "),
          retailer_slug:       slug.downcase,
          price_cents:         price_cents,
          regular_price_cents: regular_cts,
          currency:            "EUR",
          unit:                parse_unit(raw["description"]),
          quantity_text:       raw["description"].presence,
          image_url:           raw.dig("offerImages", "url", "normal").presence ||
                               raw.dig("offerImages", "url", "thumbnail").presence,
          source_url:          format(PAGE_URL_TEMPLATE, slug),
          valid_from:          parse_date(raw["validFrom"]),
          valid_until:         parse_date(raw["validUntil"])
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

      def http_get(url)
        uri  = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        req  = Net::HTTP::Get.new(
          uri.request_uri,
          "User-Agent"      => USER_AGENT,
          "Accept"          => "text/html,application/xhtml+xml",
          "Accept-Language" => "de-DE,de;q=0.9"
        )
        resp = http.request(req)
        return resp.body if resp.is_a?(Net::HTTPSuccess)

        Rails.logger.warn("[KaufDA::Offers] HTTP #{resp.code} for #{url}")
        nil
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError,
             Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
        Rails.logger.warn("[KaufDA::Offers] #{e.class}: #{e.message} (#{url})")
        nil
      end
    end
  end
end
