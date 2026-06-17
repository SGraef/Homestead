# frozen_string_literal: true
# typed: false

require "net/http"
require "json"
require "uri"
require "rexml/document"

module Flaschenpost
  # Adapter for flaschenpost.de's reverse-engineered product API.
  #
  # Their site is a Vue SPA that resolves products via a session-bound
  # warehouse_id derived from the user's delivery ZIP. The mapping
  # ZIP -> warehouse_id isn't exposed via a clean lookup endpoint, so
  # this adapter is opt-in per household: a member finds the right
  # integer once in their browser's network tab (filter for any request
  # to /php-product-api/v1/products/.../warehouse/<N>/... while browsing
  # flaschenpost.de with their ZIP set) and saves it on the Household
  # record. OfferSyncer reads it and passes it in here.
  #
  # Discovery flow per sync:
  #   1. Pull sitemap_p.xml (one fetch, ~540 KB, 4k+ product URLs).
  #   2. For each slug, hit the product page HTML (3 KB) and extract
  #      `pageType.productId` from the inline <script type="application/json">.
  #      This mapping is stable, so it's memoised in Rails.cache for a
  #      day -- subsequent runs only resolve newly-listed slugs.
  #   3. Batch the productIds in groups of BATCH_SIZE and call the
  #      PDP endpoint to get prices + variant data.
  #
  # FLASCHENPOST_MAX_PRODUCTS caps how many slugs we resolve per run so
  # a misconfiguration can't accidentally hammer their server. Default
  # 200 -- raise it once you've confirmed your warehouse_id is right.
  class Offers
    SITEMAP_URL  = "https://www.flaschenpost.de/sitemap_p.xml"
    PDP_URL_FMT  = "https://www.flaschenpost.de/php-product-api/v1/products/pdp/warehouse/%<wh>d?ids=%<ids>s"
    PRODUCT_URL  = "https://www.flaschenpost.de%<path>s"

    USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
    OPEN_TIMEOUT = 6
    READ_TIMEOUT = 15

    BATCH_SIZE       = 50
    DEFAULT_MAX      = 200
    SLUG_CACHE_TTL   = 1.day

    # Pin valid_until conservatively. Flaschenpost doesn't expose
    # discount validity, so let sweep_expired retire offers naturally
    # if a daily sync stops returning them.
    VALIDITY_DAYS = 7

    RETAILER_NAME = "flaschenpost"
    RETAILER_SLUG = "flaschenpost"

    OfferData = Struct.new(
      :external_id, :title, :brand, :category,
      :retailer_name, :retailer_slug,
      :price_cents, :regular_price_cents, :currency,
      :unit, :quantity_text, :image_url, :source_url,
      :valid_from, :valid_until,
      keyword_init: true
    )

    class << self
      # @param warehouse_id [Integer] required -- the region-specific
      #   warehouse that owns the product+price catalog. Coming from
      #   Household#flaschenpost_warehouse_id via OfferSyncer.
      # @param max_products [Integer, nil] cap on slugs resolved per
      #   run. Defaults to FLASCHENPOST_MAX_PRODUCTS or {DEFAULT_MAX}.
      # @return [Array<OfferData>]
      def pull_all(warehouse_id:, max_products: nil)
        wh = warehouse_id.to_i
        if wh.zero?
          Rails.logger.info("[Flaschenpost::Offers] warehouse_id missing; skipping")
          return []
        end

        max = (max_products || ENV["FLASCHENPOST_MAX_PRODUCTS"] || DEFAULT_MAX).to_i

        slugs = sitemap_slugs.first(max)
        return [] if slugs.empty?

        slug_to_id = resolve_product_ids(slugs)
        return [] if slug_to_id.empty?

        out = []
        slug_to_id.values.each_slice(BATCH_SIZE) do |batch|
          fetch_pdp_batch(batch, warehouse: wh).each do |raw|
            built = build(raw)
            out << built if built
          end
        end
        out
      end

      # ---- discovery ------------------------------------------------------

      def sitemap_slugs
        xml = get_text(SITEMAP_URL)
        return [] if xml.blank?

        REXML::Document.new(xml).get_elements("//url/loc").map do |el|
          URI.parse(el.text).path
        end.uniq
      end

      # Returns { "/p/brand/slug" => productId } using Rails.cache to
      # avoid re-resolving slugs we've seen before.
      def resolve_product_ids(slugs)
        out = {}
        slugs.each do |slug_path|
          pid = Rails.cache.fetch(cache_key(slug_path), expires_in: SLUG_CACHE_TTL) do
            extract_product_id(slug_path)
          end
          out[slug_path] = pid if pid
        end
        out
      end

      def cache_key(slug_path)
        ["flaschenpost", "product_id", slug_path]
      end

      def extract_product_id(slug_path)
        html = get_text(format(PRODUCT_URL, path: slug_path))
        return nil if html.blank?

        m = html.match(%r{<script[^>]*type=["']application/json["'][^>]*>(.*?)</script>}m)
        return nil unless m

        json = JSON.parse(m[1])
        json.dig("pageType", "productId")
      rescue JSON::ParserError
        nil
      end

      # ---- PDP batch fetch ------------------------------------------------

      def fetch_pdp_batch(product_ids, warehouse:)
        url  = format(PDP_URL_FMT, wh: warehouse, ids: product_ids.join(","))
        data = get_json(url)
        return [] unless data.is_a?(Array)

        data
      end

      # ---- transform ------------------------------------------------------

      def build(raw)
        return nil unless raw.is_a?(Hash)

        ext_id = raw["key"].to_s
        return nil if ext_id.empty?

        title = de(raw["name"])
        return nil if title.blank?

        master = raw["masterVariant"] || {}
        price_cents = master.dig("price", "value", "centAmount")
        return nil if price_cents.nil?

        attrs       = master["attributes"].is_a?(Array) ? master["attributes"] : []
        regular_cts = detect_regular_price(attrs, price_cents)

        OfferData.new(
          external_id:         ext_id,
          title:               title.strip,
          brand:               brand_from(raw),
          category:            category_from(raw),
          retailer_name:       RETAILER_NAME,
          retailer_slug:       RETAILER_SLUG,
          price_cents:         price_cents.to_i,
          regular_price_cents: regular_cts,
          currency:            "EUR",
          unit:                nil,
          quantity_text:       quantity_text_from(attrs),
          image_url:           image_from(master),
          source_url:          product_url_from(raw),
          valid_from:          Date.current,
          valid_until:         Date.current + VALIDITY_DAYS
        )
      end

      def de(localised)
        return nil unless localised.is_a?(Hash)

        localised["de-DE"] || localised.values.first
      end

      # Walk categories, find the one tagged fp-category-brand.
      def brand_from(raw)
        Array(raw["categories"]).each do |c|
          obj = c["obj"] || {}
          return de(obj["name"]) if obj.dig("custom", "type", "key") == "fp-category-brand"

          # Also scan ancestors -- some products only carry the brand
          # category as an ancestor of the leaf subcategory.
          Array(obj["ancestors"]).each do |a|
            aobj = a["obj"] || {}
            return de(aobj["name"]) if aobj.dig("custom", "type", "key") == "fp-category-brand"
          end
        end
        nil
      end

      # Pick the top-level fp-category (e.g. "Limo & Saft").
      def category_from(raw)
        Array(raw["categories"]).each do |c|
          obj = c["obj"] || {}
          Array(obj["ancestors"]).reverse_each do |a|
            aobj = a["obj"] || {}
            return de(aobj["name"]) if aobj.dig("custom", "type", "key") == "fp-category"
          end
          return de(obj["name"]) if obj.dig("custom", "type", "key") == "fp-category"
        end
        nil
      end

      # The PDP payload is positional and unlabeled. The pack-size text
      # ("12 x 0,5L (Glas)") consistently shows up in the attribute set.
      # Pick the first string value that matches that shape.
      def quantity_text_from(attrs)
        attrs.each do |a|
          v = a["value"]
          return v.strip if v.is_a?(String) && v.match?(/\d[\d.,]*\s*(L|ml|kg|g|x)/i)
        end
        nil
      end

      # The attribute set carries quantity-tier centAmounts. Take the
      # MAX as a proxy for "regular price" -- bulk-discount tiers all
      # sit below the single-unit list price.
      def detect_regular_price(attrs, current_price)
        tier_prices = attrs.filter_map do |a|
          # Attribute values are heterogeneous -- strings, bools, hashes.
          # Only the money-shaped hashes carry a centAmount.
          v = a["value"]
          v.is_a?(Hash) ? v["centAmount"] : nil
        end
        return nil if tier_prices.empty?

        max_tier = tier_prices.max
        return nil unless max_tier.is_a?(Integer)
        return nil if max_tier <= current_price.to_i

        max_tier
      end

      def image_from(master)
        Array(master["images"]).first&.dig("url")
      end

      def product_url_from(raw)
        slug = de(raw["slug"])
        return nil if slug.blank?

        "https://www.flaschenpost.de/p/#{raw["key"]}/#{slug}"
      end

      # ---- HTTP ------------------------------------------------------------

      def get_json(url)
        body = get_text(url, accept: "application/json")
        return nil if body.blank?

        JSON.parse(body)
      rescue JSON::ParserError => e
        Rails.logger.warn("[Flaschenpost::Offers] JSON parse failed for #{url}: #{e.message}")
        nil
      end

      def get_text(url, accept: "*/*")
        uri = URI.parse(url)
        SafeHttp.validate_uri!(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        req = Net::HTTP::Get.new(
          uri.request_uri,
          "User-Agent"      => USER_AGENT,
          "Accept"          => accept,
          "Accept-Language" => "de-DE,de;q=0.9"
        )
        resp = http.request(req)
        return resp.body if resp.is_a?(Net::HTTPSuccess)

        Rails.logger.warn("[Flaschenpost::Offers] HTTP #{resp.code} for #{url}")
        nil
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError,
             Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
        Rails.logger.warn("[Flaschenpost::Offers] #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
