# frozen_string_literal: true
# typed: false

class MealPlanEntriesController < ApplicationController
  before_action :ensure_household

  def create
    entry = current_household.meal_plan_entries.build(entry_params)
    if entry.save
      redirect_to meal_plan_path(date: entry.planned_on.iso8601),
                  notice: t("meal_plan.entry_added", recipe: entry.recipe.name)
    else
      redirect_to meal_plan_path(date: params.dig(:meal_plan_entry, :planned_on)),
                  alert: entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    entry = current_household.meal_plan_entries.find(params[:id])
    date  = entry.planned_on
    entry.destroy
    redirect_to meal_plan_path(date: date.iso8601),
                notice: t("meal_plan.entry_removed")
  end

  private

  def entry_params
    params.require(:meal_plan_entry)
          .permit(:recipe_id, :planned_on, :slot, :servings, :notes)
  end

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end
end
