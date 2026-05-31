# frozen_string_literal: true
# typed: true

# Pulls every available current offer for a household and writes/updates
# {Offer} rows.
#
# Two upstream sources today, each handled the same way:
#
#   * Marktguru (api.marktguru.de) — postcode-localized industry feeds.
#   * kaufDA  (www.kaufda.de)      — retailer-specific SSR pages.
#
# Both adapters return Struct objects with the same surface (title,
# brand, price, retailer, validity, ...) so the dispatch logic below is
# source-agnostic. {Offer#source} carries the origin string so the
# unique-key `(household, source, external_id)` keeps each upstream's
# IDs distinct.
#
# A household needs `postal_code` set, otherwise this is a no-op.
class OfferSyncer
  Result = Struct.new(:created, :updated, :expired, keyword_init: true) do
    def total = created + updated
  end

  # @param household [Household]
  def initialize(household)
    @household   = household
    @postal_code = household.postal_code.to_s.strip
  end

  # @return [Result, nil] nil when the household has no postcode configured.
  def call
    return nil if @postal_code.empty?

    @product_index    = build_product_index
    @blocklist        = @household.offer_blocklist_entries.pluck(:pattern).map { |p| p.to_s.downcase }
    @retailer_filters = @household.offer_retailer_filters.pluck(:retailer).map(&:downcase)

    created = updated = 0

    process(Marktguru::Offers.pull_all(postal_code: @postal_code), source: "marktguru") do |c, u|
      created += c
      updated += u
    end

    process(Kaufda::Offers.pull_all(postal_code: @postal_code), source: "kaufda") do |c, u|
      created += c
      updated += u
    end

    # Full ALDI Nord catalog via meinprospekt.de's public search API.
    # No auth required; paginates by `offset`. Default queries can be
    # extended via MEINPROSPEKT_QUERIES (e.g. "ALDI Nord,Aldi Süd,Tegut")
    # for any retailer covered by meinprospekt but missed by Marktguru
    # and kaufDA's retailer-page adapter.
    process(MeinProspekt::Offers.pull_all, source: "meinprospekt") do |c, u|
      created += c
      updated += u
    end

    # Flaschenpost (beverage delivery). Opt-in per-household via the
    # household's flaschenpost_warehouse_id setting -- their product
    # API is region-locked to that integer, and the ZIP -> warehouse
    # mapping has to be looked up once via browser devtools (see
    # app/services/flaschenpost/offers.rb). Skip cleanly if unset.
    fp_warehouse = @household.flaschenpost_warehouse_id
    if fp_warehouse.present?
      process(Flaschenpost::Offers.pull_all(warehouse_id: fp_warehouse), source: "flaschenpost") do |c, u|
        created += c
        updated += u
      end
    end

    expired = sweep_expired
    Result.new(created: created, updated: updated, expired: expired)
  end

  private

  # Iterate one source's offers through the blocklist + retailer filter,
  # then upsert. Yields [created, updated] per row so the caller can roll
  # up cross-source totals.
  def process(offers, source:)
    offers.each do |data|
      next if blocked?(data.title)
      next unless OfferRetailerFilter.allow?(@retailer_filters, data)

      # Backfill category from the household's keyword rules when the
      # adapter didn't supply one. Adapter-set categories win
      # (Marktguru's industry tag, kaufDA's section); the keyword
      # classifier fills the long tail (kaufDA / MeinProspekt / manual
      # entries) and is editable in /offers/categories.
      data.category = OfferCategorizer.classify(data.title, household: @household) if data.category.to_s.strip.empty?

      yield(*upsert(data, source: source))
    end
  end

  # Pre-load household products ordered by name length DESC so the
  # longest match wins ("Bio Vollmilch" outranks "Milch" when both
  # appear in an offer title).
  def build_product_index
    @household.products
              .where.not(name: [nil, ""])
              .order(Arel.sql("CHAR_LENGTH(name) DESC"))
              .to_a
  end

  # Returns [created_count, updated_count].
  def upsert(data, source:)
    offer = @household.offers.find_or_initialize_by(
      source:      source,
      external_id: data.external_id
    )
    new_record = offer.new_record?

    offer.assign_attributes(
      product:             match_product(data),
      store:               match_store(data.retailer_name),
      retailer_name:       data.retailer_name,
      title:               data.title,
      brand:               data.brand,
      category:            data.category,
      price_cents:         data.price_cents,
      regular_price_cents: data.regular_price_cents,
      currency:            data.currency,
      unit:                data.unit,
      quantity_text:       data.quantity_text,
      image_url:           data.image_url,
      source_url:          data.source_url,
      valid_from:          data.valid_from,
      valid_until:         data.valid_until
    )
    offer.save!
    [new_record ? 1 : 0, new_record ? 0 : 1]
  end

  # First product whose name appears as a substring in the offer title
  # (case-insensitive). Returns the longest match if several products
  # match, since #build_product_index orders accordingly.
  def match_product(data)
    title = data.title.to_s.downcase
    return nil if title.empty?

    @product_index.find { |p| title.include?(p.name.to_s.downcase) }
  end

  # Best-effort retailer → Store linkage. Trims trademark-looking suffixes
  # ("REWE Markt" → "REWE") for matching but keeps the original on the
  # offer row so the UI shows the user-facing retailer string.
  def match_store(retailer_name)
    needle = retailer_name.to_s.split(/[\s,]+/).first&.downcase
    return nil if needle.blank?

    @household.stores.find_by("LOWER(name) = ?", needle) ||
      @household.stores.where("LOWER(name) LIKE ?", "#{needle}%").first
  end

  def sweep_expired
    @household.offers
              .where("valid_until IS NOT NULL AND valid_until < ?", Date.current)
              .delete_all
  end

  # Title matches any blocklist pattern (case-insensitive substring)?
  def blocked?(title)
    OfferBlocklistEntry.match?(@blocklist, title)
  end
end
