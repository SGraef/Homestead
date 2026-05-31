# frozen_string_literal: true
# typed: false

# Picks a week of dinner recipes for a household, trying to follow
# soft "healthy" guidelines and avoid week-over-week repetition.
#
# Inputs the planner cares about:
# * Recipes used in the trailing N weeks (cooldown — don't repeat).
# * Recipe tags (vegetarian / fish / meat buckets — week-balance).
# * Days that already have a dinner entry (preserved; we only fill gaps).
#
# Health buckets are SOFT targets, not hard rules:
# * ≥ 2 vegetarian (vegetarisch / vegan) dinners per week
# * ≥ 1 fish dinner per week
# * ≤ 4 meat dinners per week
#
# When the household has fewer recipes than slots to fill, we stop
# rather than repeat. When tags are missing entirely the buckets
# silently degrade to "any recipe is fine".
class MealPlanSuggester
  TARGET_SLOT = "dinner"
  COOLDOWN_WEEKS = 4

  # Tag heuristics. Lowercase; matched case-insensitively against
  # Recipe#tag_list. German + English so both Chefkoch imports and
  # hand-entered recipes work.
  VEG_TAGS  = %w[vegetarisch vegetarian vegan].freeze
  FISH_TAGS = %w[fisch fish meeresfrüchte seafood].freeze
  MEAT_TAGS = %w[fleisch beef rind schwein pork lamm lamb hähnchen huhn chicken pute turkey wild].freeze

  # `created_entries` rather than `entries` — Struct already has an
  # `#entries` accessor and overriding it triggers Lint/StructNewOverride.
  Result = Struct.new(:created_entries, :scheduled, :skipped_days, :reason, keyword_init: true)

  def initialize(household:, week_start: nil, slot: TARGET_SLOT)
    @household   = household
    @week_start  = (week_start || Date.current).beginning_of_week(:monday)
    @slot        = slot
    @random      = Random.new # tie-breaker; deterministic with `Random.new(seed)` in specs
  end

  def call
    days = (0..6).map { |i| @week_start + i.days }

    # Day -> existing dinner entry (if any). Don't overwrite manual picks.
    existing = @household.meal_plan_entries
                         .where(planned_on: days, slot: @slot)
                         .group_by(&:planned_on)
    slots_to_fill = days.reject { |d| existing.key?(d) }

    catalog = @household.recipes.to_a
    if catalog.empty?
      return Result.new(created_entries: [], scheduled: 0, skipped_days: slots_to_fill.size,
                        reason: :no_recipes)
    end

    # Pre-load recent picks so the scorer can penalise repeats.
    cooldown_from = @week_start - (COOLDOWN_WEEKS * 7).days
    recent_recipe_ids = @household.meal_plan_entries
                                  .where(planned_on: cooldown_from..)
                                  .pluck(:recipe_id)
    cooldown_counts = recent_recipe_ids.tally

    picks       = {}
    chosen_ids  = []
    veg_count   = 0
    fish_count  = 0
    meat_count  = 0

    slots_to_fill.each do |day|
      candidates = catalog.reject { |r| chosen_ids.include?(r.id) }
      break if candidates.empty?

      scored = candidates.map do |r|
        [r, score_recipe(r, cooldown_counts: cooldown_counts,
                            veg_count:       veg_count,
                            fish_count:      fish_count,
                            meat_count:      meat_count)]
      end

      # Weighted-random pick from the top quartile so a tie between
      # high-scoring recipes doesn't always resolve to the same one
      # week-over-week.
      max_score = scored.map(&:last).max
      top       = scored.select { |_, s| s >= max_score - 25 }
      chosen, = top.sample(random: @random)

      picks[day] = chosen
      chosen_ids << chosen.id
      veg_count  += 1 if chosen.tagged_with_any?(VEG_TAGS)
      fish_count += 1 if chosen.tagged_with_any?(FISH_TAGS)
      meat_count += 1 if chosen.tagged_with_any?(MEAT_TAGS)
    end

    # Persist as MealPlanEntry rows in a single transaction so a
    # failure in one doesn't leave a half-suggested week behind.
    created = []
    MealPlanEntry.transaction do
      picks.each do |day, recipe|
        created << @household.meal_plan_entries.create!(
          recipe:     recipe,
          planned_on: day,
          slot:       @slot,
          servings:   recipe.servings
        )
      end
    end

    Result.new(
      created_entries: created,
      scheduled:       created.size,
      skipped_days:    slots_to_fill.size - created.size,
      reason:          nil
    )
  end

  private

  def score_recipe(recipe, cooldown_counts:, veg_count:, fish_count:, meat_count:)
    score = 100

    # Cooldown penalty: heavily disprefer recipes already cooked
    # within the trailing COOLDOWN_WEEKS window. The penalty scales
    # with how many times -- a recipe used twice recently sinks
    # below one used once.
    if (uses = cooldown_counts[recipe.id]).to_i.positive?
      score -= 60 * uses
    end

    # Health bucket boosts: encourage filling under-target buckets,
    # discourage over-shooting meat.
    if recipe.tagged_with_any?(VEG_TAGS)
      score += veg_count < 2 ? 30 : 5
    end
    if recipe.tagged_with_any?(FISH_TAGS)
      score += fish_count < 1 ? 40 : -10
    end
    if recipe.tagged_with_any?(MEAT_TAGS)
      score += meat_count < 4 ? 5 : -40
    end

    # Tiny randomness so equal-scoring recipes don't always sort the
    # same way and Monday's pick doesn't become deterministic.
    score += @random.rand(0..9)

    score
  end
end
