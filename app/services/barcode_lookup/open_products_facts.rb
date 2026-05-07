# frozen_string_literal: true
# typed: true

module BarcodeLookup
  # Open Products Facts — sister project of Open Food Facts covering general
  # household products (cleaning supplies, paper goods, etc.). Same API shape.
  class OpenProductsFacts < Source
    SOURCE_NAME    = "open_products_facts"
    PRODUCT_URL    = "https://world.openproductsfacts.org/api/v2/product/%s.json"
    SEARCH_URL     = "https://world.openproductsfacts.org/cgi/search.pl"
    PAGE_TEMPLATE  = "https://world.openproductsfacts.org/product/%s"
    SEARCH_FIELDS  = %w[code product_name product_name_de brands
                        categories_tags quantity image_front_url].join(",")

    # @param barcode [String]
    # @return [BarcodeLookup::Result, nil]
    def self.fetch(barcode)
      code = OpenFoodFacts.sanitize(barcode)
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
        search_terms: terms
      }
      params[:brands_tags] = brand unless brand.empty?

      data = get_json("#{SEARCH_URL}?#{URI.encode_www_form(params)}")
      return [] unless data && data["products"].is_a?(Array)

      data["products"].filter_map do |p|
        build_result(p, source_name: SOURCE_NAME, page_template: PAGE_TEMPLATE)
      end.first(limit)
    end
  end
end
