# frozen_string_literal: true
# typed: false

# Quick add/delete for ingredients from the recipe show page, so
# users can append after a recipe has been saved without going back
# through the full edit form.
class RecipeIngredientsController < ApplicationController
  before_action :ensure_household
  before_action :set_recipe

  def create
    ingredient = @recipe.recipe_ingredients.build(ingredient_params)
    if ingredient.save
      redirect_to @recipe, notice: t("recipe.ingredient_added")
    else
      redirect_to @recipe, alert: ingredient.errors.full_messages.to_sentence
    end
  end

  def destroy
    ingredient = @recipe.recipe_ingredients.find(params[:id])
    ingredient.destroy
    redirect_to @recipe, notice: t("recipe.ingredient_removed")
  end

  private

  def set_recipe
    @recipe = current_household.recipes.find(params[:recipe_id])
  end

  def ingredient_params
    params.require(:recipe_ingredient).permit(:product_id, :quantity, :unit, :notes, :position)
  end

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end
end
