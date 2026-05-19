# frozen_string_literal: true
# typed: true

module BarcodeLookup
  # Marktguru (https://www.marktguru.de) — German grocery flyer / offer
  # aggregator. They cover commercial-store SKUs that the open community
  # databases (Open Food Facts / Open Products Facts) often miss, and they
  # carry richer brand + image data for DE products.
  #
  # ⚠️ This is a *reverse-engineered* private JSON API used by their web app.
  # No public contract; expect endpoints / field names to change without
  # warning. We parse defensively, swallow any structural surprises, and let
  # {BarcodeLookup} log + skip on failure so a broken adapter never breaks a
  # scan flow.
  #
  # Endpoints (all under https://www.marktguru.de):
  #   GET /api/v1/products/searchByEan?ean=<barcode>
  #   GET /api/v1/products?query=<terms>&pageSize=<n>
  #
  # Response shape (typical):
  #   { "results": [
  #       { "id": 123,
  #         "name": "Bio Vollmilch 1L",
  #         "brand": "Alnatura",
  #         "category": { "name": "Milch & Käse" },
  #         "amount": "1 L",
  #         "ean": ["4006381333924"],
  #         "imageUrl": "https://media.marktguru.de/.../12345.jpg" } ],
  #     "totalCount": 1 }
  class Marktguru < Source
    SOURCE_NAME    = "marktguru"
    BASE_URL       = "https://www.marktguru.de"
    EAN_URL        = "#{BASE_URL}/api/v1/products/searchByEan?ean=%s"
    SEARCH_URL     = "#{BASE_URL}/api/v1/products"
    PAGE_TEMPLATE  = "#{BASE_URL}/produkte/%s"
    BROWSER_UA     = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:124.0) " \
                     "Gecko/20100101 Firefox/124.0"
    BROWSER_HDRS   = { "Origin" => BASE_URL, "Referer" => "#{BASE_URL}/" }.freeze

    # @param barcode [String]
    # @return [BarcodeLookup::Result, nil]
    def self.fetch(barcode)
      code = barcode.to_s.gsub(/\D/, "")
      return nil if code.empty?

      data = get_json(format(EAN_URL, code),
                      user_agent: BROWSER_UA, headers: BROWSER_HDRS)
      product = first_product(data)
      build(product, code)
    end

    # @param name  [String]
    # @param brand [String]
    # @param limit [Integer]
    # @return [Array<BarcodeLookup::Result>]
    def self.search(name:, brand:, limit: 5)
      query = [name, brand].compact_blank.join(" ").strip
      return [] if query.empty?

      url = "#{SEARCH_URL}?#{URI.encode_www_form(query: query, pageSize: limit)}"
      data = get_json(url, user_agent: BROWSER_UA, headers: BROWSER_HDRS)
      list = Array(data && data["results"])
      list.first(limit).filter_map { |p| build(p, p["ean"]) }
    end

    # Marktguru returns either a single object on `searchByEan` or a list
    # under `results` -- normalize both shapes here.
    def self.first_product(data)
      return nil unless data.is_a?(Hash)
      return data["results"].first if data["results"].is_a?(Array)

      data["product"] || data
    end

    # Build a {BarcodeLookup::Result} from a Marktguru product hash. `ean`
    # may be a String or an Array<String> depending on endpoint.
    def self.build(product, ean)
      return nil unless product.is_a?(Hash)

      code = Array(ean).flatten.compact.first.to_s.gsub(/\D/, "")
      return nil if code.empty?

      name = product["name"].to_s.strip
      return nil if name.empty?

      Result.new(
        source:        SOURCE_NAME,
        source_url:    format(PAGE_TEMPLATE, product["id"] || code),
        barcode:       code,
        name:          name,
        brand:         product["brand"].presence,
        category:      product.dig("category", "name").presence,
        unit:          parse_unit(product["amount"]),
        quantity_text: product["amount"].presence,
        image_url:     product["imageUrl"].presence
      )
    end
  end
end
