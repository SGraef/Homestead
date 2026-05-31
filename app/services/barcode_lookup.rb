# frozen_string_literal: true
# typed: true

# Lookup pipeline for public product databases.
#
# Two entry points:
#
#   * {.call(barcode)}              — exact-match lookup; returns one {Result} or nil
#   * {.search(name:, brand:)}      — fuzzy search; returns up to `limit` Results
#
# Sources are tried in order; the first one with results wins. Network failures
# are swallowed and logged so a flaky upstream never breaks the user-facing flow.
module BarcodeLookup
  # Normalised payload returned by every source so controllers and views
  # don't need to know which database answered.
  Result = Struct.new(
    :source,        # e.g. "open_food_facts"
    :source_url,    # canonical URL on the upstream site
    :barcode,
    :name,
    :brand,
    :category,
    :unit,          # one of Product::UNITS, or nil
    :quantity_text,
    :image_url,
    keyword_init: true
  )

  # Lookup order matters: open community DBs first (stable schemas, open
  # license), then Marktguru as a DE-focused commercial fallback for
  # supermarket SKUs the open DBs don't carry. Marktguru's API is
  # reverse-engineered and may break -- keeping it last means upstream
  # breakage degrades to "no extra hits", not "scan flow broken".
  # @return [Array<Class>]
  def self.sources
    [OpenFoodFacts, OpenProductsFacts, Marktguru]
  end

  # Lookup by barcode (exact match).
  # @param barcode [String]
  # @return [Result, nil]
  def self.call(barcode)
    code = barcode.to_s.strip
    return nil if code.empty?

    sources.each do |source|
      result = safe_fetch(source, code)
      return result if result
    end
    nil
  end

  # Search by name and/or brand. Returns the first non-empty list across the
  # source chain (so we don't surface duplicate hits from two databases).
  # @param name [String, nil]
  # @param brand [String, nil]
  # @param limit [Integer]
  # @return [Array<Result>]
  def self.search(name: nil, brand: nil, limit: 5)
    query = { name: name.to_s.strip, brand: brand.to_s.strip }
    return [] if query[:name].empty? && query[:brand].empty?

    sources.each do |source|
      next unless source.respond_to?(:search)

      results = safe_search(source, query, limit)
      return results if results.any?
    end
    []
  end

  # Caching only writes hits: a transient upstream blip must not poison the
  # next 24h of lookups for a real product.
  def self.safe_fetch(source, code)
    key = ["barcode_lookup", source.name, code]
    if (cached = Rails.cache.read(key))
      return cached
    end

    result = source.fetch(code)
    Rails.cache.write(key, result, expires_in: 1.day) if result
    result
  rescue StandardError => e
    Rails.logger.warn("[BarcodeLookup] #{source.name} fetch #{code} failed: #{e.class}: #{e.message}")
    nil
  end

  def self.safe_search(source, query, limit)
    key = ["barcode_search", source.name, query, limit]
    if (cached = Rails.cache.read(key))
      return cached
    end

    results = source.search(name: query[:name], brand: query[:brand], limit: limit)
    Rails.cache.write(key, results, expires_in: 1.day) if results.any?
    results
  rescue StandardError => e
    Rails.logger.warn("[BarcodeLookup] #{source.name} search #{query.inspect} failed: #{e.class}: #{e.message}")
    []
  end
end
