# frozen_string_literal: true
# typed: true

# Classifies an offer title (e.g. "Hähnchen Innenfilets", "Saure
# Glühwürmchen") into a household-defined German category by matching
# against {OfferCategory} keywords.
#
# Match shape: case-insensitive substring. Walks the household's
# categories by position ASC, then by name; within each category the
# longest keyword is tried first so more-specific terms win over
# generic ones. Returns nil when no keyword matches — nil propagates
# through to the "Sonstige / Other" group on /offers.
#
# Mapping per household is cached in `Rails.cache`, keyed by the
# latest updated_at across the category + keyword rows. Editing a
# keyword in the web UI bumps that timestamp and naturally invalidates
# the cache.
class OfferCategorizer
  class << self
    # @param title [String]
    # @param household [Household]
    # @return [String, nil] category name, or nil if nothing matches
    def classify(title, household:)
      needle = normalise(title)
      return nil if needle.empty?
      return nil unless household

      mapping_for(household).each do |category_name, keywords|
        return category_name if keywords.any? { |kw| needle.include?(kw) }
      end
      nil
    end

    # Strip German umlauts (and similar) so a keyword stored as "apfel"
    # still matches a title that wrote "Äpfel" — the substring match
    # is byte-level and `"äpfel".include?("apfel")` would otherwise
    # return false. `I18n.transliterate` covers the German pairs
    # (ä→a, ö→o, ü→u, ß→ss) without bringing in another dependency.
    def normalise(s)
      I18n.transliterate(s.to_s).downcase.strip
    end

    # @return [Array<[String, Array<String>]>] [[category, [keyword,…]],…]
    # Keywords are transliterated the same way as titles so umlaut
    # forms match interchangeably ("Äpfel" hits keyword "apfel").
    def mapping_for(household)
      Rails.cache.fetch(cache_key(household)) do
        household.offer_categories
                 .ordered
                 .includes(:offer_category_keywords)
                 .map do |cat|
                   kws = cat.offer_category_keywords
                            .map { |k| normalise(k.keyword) }
                            .reject(&:empty?)
                            .uniq
                            .sort_by { |k| -k.length }
                   [cat.name, kws]
                 end
      end
    end

    # Cache key includes the most recent updated_at across both tables
    # so any edit (rename, reorder, keyword add/remove) auto-invalidates.
    def cache_key(household)
      stamps = [
        household.offer_categories.maximum(:updated_at),
        OfferCategoryKeyword.joins(:offer_category)
                             .where(offer_categories: { household_id: household.id })
                             .maximum(:updated_at)
      ].compact
      version = stamps.max&.to_i || 0
      ["offer_categorizer_v2", household.id, version]
    end
  end
end
