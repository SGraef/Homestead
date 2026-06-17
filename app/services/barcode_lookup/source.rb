# frozen_string_literal: true
# typed: false

require "net/http"
require "json"
require "uri"

module BarcodeLookup
  # Common HTTP plumbing for upstream product databases. Subclasses implement
  # {.fetch(barcode)} and {.search(name:, brand:, limit:)}, returning a
  # {BarcodeLookup::Result} or an array of them.
  class Source
    USER_AGENT     = "Homestead/0.1 (+https://homestead.local)"
    OPEN_TIMEOUT   = 8
    READ_TIMEOUT   = 10
    MAX_REDIRECTS  = 3

    class << self
      # @param url [String]
      # @param user_agent [String] override the default Homestead UA -- some
      #   private APIs (e.g. Marktguru) reject non-browser-looking clients.
      # @param headers [Hash] extra request headers (Origin, Referer, …) the
      #   subclass needs to look like a browser tab.
      # @return [Hash, nil] parsed JSON body, or nil on failure (logged)
      def get_json(url, redirects: MAX_REDIRECTS, user_agent: USER_AGENT, headers: {})
        uri = URI.parse(url)
        SafeHttp.validate_uri!(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        req_headers = { "User-Agent" => user_agent,
                        "Accept"     => "application/json" }.merge(headers)
        req  = Net::HTTP::Get.new(uri.request_uri, req_headers)
        resp = http.request(req)

        case resp
        when Net::HTTPSuccess
          JSON.parse(resp.body)
        when Net::HTTPRedirection
          target = resp["location"]
          if redirects.positive? && target.present?
            target = URI.join(url, target).to_s
            get_json(target, redirects: redirects - 1, user_agent: user_agent, headers: headers)
          else
            log_warn("redirect chain exhausted at #{url}")
            nil
          end
        else
          log_warn("HTTP #{resp.code} for #{url} body=#{resp.body.to_s.truncate(200)}")
          nil
        end
      rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED,
             OpenSSL::SSL::SSLError => e
        log_warn("#{e.class}: #{e.message} (#{url})")
        nil
      end

      # Best-effort guess at one of {Product::UNITS} from a free-form upstream
      # quantity string like "1 L", "500 g", "12 pcs".
      # @param text [String, nil]
      # @return [String, nil]
      def parse_unit(text)
        return nil if text.to_s.empty?

        case text.downcase
        when /\b(?:l|liter|litre|litres)\b/    then "l"
        when /\bml\b/                          then "ml"
        when /\bkg\b/                          then "kg"
        when /\bg\b/                           then "g"
        when /\b(?:pcs|piece|pieces|stk|x)\b/  then "pcs"
        end
      end

      # Convert a single OFF/OPF product hash into a normalised {Result}.
      # `barcode` falls back to `product["code"]` (which OFF/OPF return on
      # search hits but not on direct product lookups).
      def build_result(product, source_name:, page_template:, barcode: nil)
        return nil unless product.is_a?(Hash)

        code = (barcode || product["code"]).to_s.strip
        return nil if code.empty?

        # German first. OFF returns localized fields when called against
        # de.openfoodfacts.org; world.* falls back to whatever language
        # the contributor entered, hence the multi-locale chain.
        name = product["product_name_de"].presence ||
               product["product_name"].presence ||
               product["product_name_en"].presence ||
               product["generic_name_de"].presence ||
               product["generic_name"].presence
        return nil if name.blank?

        Result.new(
          source:        source_name,
          source_url:    format(page_template, code),
          barcode:       code,
          name:          name.to_s.strip,
          brand:         product["brands"].to_s.split(",").first&.strip,
          category:      pick_category(product),
          unit:          parse_unit(product["quantity"]),
          quantity_text: product["quantity"].presence,
          image_url:     product["image_front_url"].presence ||
                         product["image_url"].presence ||
                         product.dig("selected_images", "front", "display", "de").presence
        )
      end

      def log_warn(msg)
        Rails.logger.warn("[BarcodeLookup::Source] #{name}: #{msg}")
      end

      # Pick a human-readable, ideally-German category label from an
      # OFF product hash. Priority:
      #   1. `categories` (localized comma-separated string; the `de.*`
      #      subdomain returns German labels like "Milchprodukte, Milch")
      #   2. First `de:`-prefixed tag in `categories_tags`
      #   3. Any first tag in `categories_tags`, stripped of its locale
      #      prefix (best-effort English/French/… → titleised)
      def pick_category(product)
        if (cats = product["categories"]).is_a?(String) && cats.strip.present?
          first = cats.split(",").map(&:strip).reject(&:empty?).first
          return first if first
        end

        tags = product["categories_tags"]
        return nil unless tags.is_a?(Array) && tags.any?

        de_tag = tags.find { |t| t.is_a?(String) && t.start_with?("de:") }
        chosen = de_tag || tags.first
        chosen.to_s.sub(/\A[a-z]{2}:/, "").tr("-", " ").presence
      end
    end
  end
end
