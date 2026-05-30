# frozen_string_literal: true
# typed: false

class RecipesController < ApplicationController
  before_action :ensure_household
  before_action :set_recipe, only: %i[show edit update destroy]

  def index
    @recipes = current_household.recipes.ordered
  end

  def show
    @ingredients = @recipe.recipe_ingredients.includes(:product)
    @plan_slots  = MealPlanEntry::SLOTS
  end

  def new
    @recipe = current_household.recipes.build(servings: 1)
    # Render a few blank ingredient slots up front so the new-form
    # feels usable without an "add row" button. Empty rows are
    # filtered by accepts_nested_attributes_for's reject_if.
    5.times { @recipe.recipe_ingredients.build }
  end

  def create
    @recipe = current_household.recipes.build(recipe_params)
    if @recipe.save
      redirect_to @recipe, notice: t("recipe.created", name: @recipe.name)
    else
      pad_empty_ingredient_rows
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    pad_empty_ingredient_rows
  end

  def update
    if @recipe.update(recipe_params)
      redirect_to @recipe, notice: t("recipe.updated", name: @recipe.name)
    else
      pad_empty_ingredient_rows
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @recipe.name
    @recipe.destroy
    redirect_to recipes_path, notice: t("recipe.deleted", name: name)
  end

  private

  def set_recipe
    @recipe = current_household.recipes.find(params[:id])
  end

  def pad_empty_ingredient_rows
    return unless @recipe
    needed = 3 - @recipe.recipe_ingredients.select { |i| i.new_record? }.size
    needed.positive? && needed.times { @recipe.recipe_ingredients.build }
  end

  def recipe_params
    params.require(:recipe).permit(
      :name, :description, :servings, :prep_minutes, :cook_minutes, :notes,
      recipe_ingredients_attributes: %i[
        id product_id quantity unit notes position _destroy
      ]
    )
  end

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end
end
