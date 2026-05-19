# frozen_string_literal: true
# typed: true

module BarcodeLookup
  # Open Food Facts (https://world.openfoodfacts.org) — free, open-license
  # food product database covering most consumer groceries worldwide.
  #
  # Endpoints:
  #   GET /api/v2/product/{barcode}.json   — single-product lookup
  #   GET /cgi/search.pl                    — free-text search; the v1 CGI is
  #                                           the battle-tested route for
  #                                           fuzzy name+brand queries (the
  #                                           /api/v2/search endpoint has
  #                                           inconsistent `search_terms`
  #                                           behavior).
  class OpenFoodFacts < Source
    SOURCE_NAME    = "open_food_facts"
    # `world.*` is the canonical, always-on host. We pass `lc=de` so OFF
    # surfaces German fallback names + the `de:`-prefixed tag namespace
    # in responses; the German subdomain (`de.*`) was an attractive
    # alternative but its search routes intermittently return a
    # "temporarily unavailable" HTML page, so we stay on world.
    PRODUCT_URL    = "https://world.openfoodfacts.org/api/v2/product/%s.json?lc=de"
    SEARCH_URL     = "https://world.openfoodfacts.org/cgi/search.pl"
    PAGE_TEMPLATE  = "https://world.openfoodfacts.org/product/%s"
    SEARCH_FIELDS  = %w[code product_name product_name_de brands
                        categories categories_tags quantity image_front_url].join(",")

    # @param barcode [String]
    # @return [BarcodeLookup::Result, nil]
    def self.fetch(barcode)
      code = sanitize(barcode)
      return nil if code.empty?

      data = get_json(format(PRODUCT_URL, code))
      return nil unless data && data["status"].to_i == 1

      build_result(data["product"] || {},
                   barcode:       code,
                   source_name:   SOURCE_NAME,
                   page_template: PAGE_TEMPLATE)
    end

    # @param name  [String]
    # @param brand [String]
    # @param limit [Integer]
    # @return [Array<BarcodeLookup::Result>]
    def self.search(name:, brand:, limit: 5)
      terms = [name, brand].compact_blank.join(" ").strip
      return [] if terms.empty?

      params = {
        action:       "process",
        json:         "1",
        page_size:    limit,
        fields:       SEARCH_FIELDS,
        lc:           "de",
        search_terms: terms
      }
      params[:brands_tags] = brand unless brand.empty?

      data = get_json("#{SEARCH_URL}?#{URI.encode_www_form(params)}")
      return [] unless data && data["products"].is_a?(Array)

      data["products"].filter_map do |p|
        build_result(p, source_name: SOURCE_NAME, page_template: PAGE_TEMPLATE)
      end.first(limit)
    end

    # OFF accepts only digits; strip whitespace, hyphens, NBSPs etc. that
    # tend to slip in when copy-pasting from product pages.
    def self.sanitize(barcode)
      barcode.to_s.gsub(/\D/, "")
    end
  end
end
