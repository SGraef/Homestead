# frozen_string_literal: true
# typed: false

# A household-scoped recipe: a name, optional prep/cook timings, and
# a list of ingredients pulled from the household's Product catalog.
# Used by the meal-plan view to surface "what we're cooking this week
# and what's missing from storage".
class Recipe < ApplicationRecord
  belongs_to :household
  has_many :recipe_ingredients, -> { order(:position, :id) },
           dependent:    :destroy,
           inverse_of:   :recipe
  has_many :products, through: :recipe_ingredients
  has_many :meal_plan_entries, dependent: :destroy

  accepts_nested_attributes_for :recipe_ingredients,
                                allow_destroy: true,
                                # Drop blank rows the form helpfully renders for
                                # quick batch entry, but keep partial rows so the
                                # user sees the validation error and can correct.
                                reject_if: ->(attrs) {
                                  attrs[:product_id].blank? && attrs[:quantity].blank?
                                }

  validates :name,     presence: true, length: { maximum: 200 }
  validates :servings, numericality: { only_integer: true, greater_than: 0 }
  validates :prep_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                            allow_nil: true
  validates :cook_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                            allow_nil: true

  scope :ordered, -> { order(:name) }

  # @return [Integer] prep + cook minutes; 0 when both are unset.
  def total_minutes
    (prep_minutes || 0) + (cook_minutes || 0)
  end

  # Comma-split, lowercased, deduped tag list. Robust to nil + whitespace.
  # @return [Array<String>]
  def tag_list
    tags.to_s.downcase.split(",").map(&:strip).reject(&:empty?).uniq
  end

  # Accepts either an array or a comma-separated string. Canonicalised to
  # a single comma-space-separated string so plain SQL `LIKE` queries
  # against the column stay simple.
  def tag_list=(value)
    raw = value.is_a?(Array) ? value : value.to_s.split(",")
    self.tags = raw.map { |t| t.to_s.strip }.reject(&:empty?).uniq.join(", ")
  end

  # True if any tag in `needles` (case-insensitive) appears on this
  # recipe. Used by MealPlanSuggester's health-bucket scoring.
  def tagged_with_any?(needles)
    return false if tag_list.empty?
    set = tag_list.to_set
    Array(needles).any? { |t| set.include?(t.to_s.downcase) }
  end
end
