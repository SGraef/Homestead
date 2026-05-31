# frozen_string_literal: true
# typed: true

# Seeds a household's offer categories from the YAML factory defaults at
# `config/offer_categories.yml`. Runs:
#
#   * on Household creation (after_create) -- new households start with
#     the same baseline mapping every developer sees
#   * from the data migration -- existing households get seeded once
#   * via the "Reset to defaults" button on /offers/categories
#
# Idempotent: callers can pass `replace: true` to wipe and re-seed
# (used by the reset button); the default (`replace: false`) only seeds
# when the household has no categories yet, so it's safe to call from
# multiple places.
class OfferCategorySeeder
  DEFAULTS_PATH = Rails.root.join("config/offer_categories.yml")

  # @param household [Household]
  # @param replace [Boolean] when true, drop existing categories first
  # @return [Integer] number of categories seeded
  def self.call(household, replace: false)
    new(household).call(replace: replace)
  end

  def initialize(household)
    @household = household
  end

  def call(replace: false)
    return 0 if !replace && @household.offer_categories.exists?

    defaults = load_defaults
    return 0 if defaults.empty?

    OfferCategory.transaction do
      @household.offer_categories.destroy_all if replace

      defaults.each_with_index do |(name, keywords), i|
        cat = @household.offer_categories.create!(
          name:     name,
          position: (i + 1) * 10 # leave gaps so manual reorders are easier
        )
        Array(keywords).filter_map { |k| k.to_s.strip.presence }.uniq.each do |kw|
          # `create` (not `create!`): if the YAML lists collation-twin
          # variants like "apfel" + "äpfel" that MySQL's ai_ci unique
          # index treats as equal, we skip the dupe silently instead
          # of blowing up the whole seed.
          cat.offer_category_keywords.create(keyword: kw)
        end
      end
    end

    defaults.size
  end

  private

  def load_defaults
    return {} unless File.exist?(DEFAULTS_PATH)

    YAML.safe_load_file(DEFAULTS_PATH) || {}
  rescue Psych::SyntaxError => e
    Rails.logger.warn("[OfferCategorySeeder] YAML parse failed: #{e.message}")
    {}
  end
end
