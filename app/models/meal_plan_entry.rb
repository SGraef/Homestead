# frozen_string_literal: true
# typed: false

# One scheduled recipe on the household's weekly meal plan. A given
# (date, slot) can hold several entries -- the weekly view stacks
# them inside the cell so a "kids' option" alongside the main dinner
# is just two entries.
class MealPlanEntry < ApplicationRecord
  SLOTS = %w[breakfast lunch dinner snack].freeze

  belongs_to :household
  belongs_to :recipe

  validates :planned_on, presence: true
  validates :slot, presence: true, inclusion: { in: SLOTS }
  validates :servings, numericality: { greater_than: 0 }
  validate  :recipe_must_match_household

  scope :for_week_of, ->(date) {
    monday = date.beginning_of_week(:monday)
    where(planned_on: monday..(monday + 6.days))
  }

  # Convenience: positional index of the slot so the UI can sort
  # entries the way humans read a day.
  def self.slot_index(slot)
    SLOTS.index(slot.to_s) || SLOTS.size
  end

  private

  def recipe_must_match_household
    return unless recipe && household && recipe.household_id != household_id

    errors.add(:recipe, :wrong_household)
  end
end
