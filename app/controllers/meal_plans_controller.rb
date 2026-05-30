# frozen_string_literal: true
# typed: false

# Weekly meal-plan grid. The view is keyed by `?date=YYYY-MM-DD`
# (default: today). We always render the Mon-Sun week containing
# that date.
class MealPlansController < ApplicationController
  before_action :ensure_household

  def show
    anchor   = parse_anchor_date(params[:date]) || Date.current
    @monday  = anchor.beginning_of_week(:monday)
    @days    = (0..6).map { |i| @monday + i.days }
    @slots   = MealPlanEntry::SLOTS

    entries = current_household.meal_plan_entries
                                .for_week_of(@monday)
                                .includes(:recipe)
                                .order(:planned_on, :id)
    @entries_by_cell = entries.group_by { |e| [e.planned_on, e.slot] }
    @recipes = current_household.recipes.ordered
  end

  private

  def parse_anchor_date(raw)
    return nil if raw.blank?
    Date.iso8601(raw.to_s)
  rescue ArgumentError, Date::Error
    nil
  end

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end
end
