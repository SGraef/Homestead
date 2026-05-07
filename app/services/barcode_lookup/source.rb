# frozen_string_literal: true
# typed: true

require "net/http"
require "json"
require "uri"

module BarcodeLookup
  # Common HTTP plumbing for upstream product databases. Subclasses implement
  # {.fetch(barcode)} and {.search(name:, brand:, limit:)}, returning a
  # {BarcodeLookup::Result} or an array of them.
  class Source
    USER_AGENT     = "Pantria/0.1 (+https://pantria.local)"
    OPEN_TIMEOUT   = 8
    READ_TIMEOUT   = 10
    MAX_REDIRECTS  = 3

    class << self
      # @param url [String]
      # @return [Hash, nil] parsed JSON body, or nil on failure (logged)
      def get_json(url, redirects: MAX_REDIRECTS)
        uri  = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl     = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        req  = Net::HTTP::Get.new(uri.request_uri,
                                  "User-Agent" => USER_AGENT,
                                  "Accept"     => "application/json")
        resp = http.request(req)

        case resp
        when Net::HTTPSuccess
          JSON.parse(resp.body)
        when Net::HTTPRedirection
          target = resp["location"]
          if redirects.positive? && target.present?
            target = URI.join(url, target).to_s
            get_json(target, redirects: redirects - 1)
          else
            log_warn("redirect chain exhausted at #{url}")
            nil
          end
        else
          log_warn("HTTP #{resp.code} for #{url} body=#{resp.body.to_s.truncate(200)}")
          nil
        end
      rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
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

        name = product["product_name"].presence ||
               product["product_name_en"].presence ||
               product["product_name_de"].presence ||
               product["generic_name"].presence
        return nil if name.blank?

        Result.new(
          source:        source_name,
          source_url:    format(page_template, code),
          barcode:       code,
          name:          name.to_s.strip,
          brand:         product["brands"].to_s.split(",").first&.strip,
          category:      product["categories_tags"]&.first&.sub(/\A[a-z]{2}:/, "")&.tr("-", " "),
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
    end
  end
end
