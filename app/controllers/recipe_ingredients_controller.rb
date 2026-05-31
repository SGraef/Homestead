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

  # POST /recipes/:recipe_id/ingredients/:id/consume -- "Used" button:
  # decrement storage_items for this ingredient's product by its
  # quantity. Walks storage rows soonest-to-expire first; if the
  # household doesn't have enough on hand, flashes a "short by N"
  # notice so the user can see what's missing.
  def consume
    ingredient = @recipe.recipe_ingredients.find(params[:id])
    result     = ingredient.consume_from_storage!

    if !result.ok?
      redirect_to @recipe,
                  alert: t("recipe.consume.unit_mismatch",
                           name:         ingredient.product.name,
                           row_unit:     ingredient.unit,
                           product_unit: ingredient.product.unit)
    elsif result.consumed.to_d.zero?
      redirect_to @recipe,
                  alert: t("recipe.consume.nothing_on_hand",
                           name: ingredient.product.name)
    elsif result.short?
      redirect_to @recipe,
                  notice: t("recipe.consume.short",
                            name:     ingredient.product.name,
                            consumed: format_qty(result.consumed),
                            short:    format_qty(result.short),
                            unit:     ingredient.display_unit)
    else
      redirect_to @recipe,
                  notice: t("recipe.consume.ok",
                            name:     ingredient.product.name,
                            consumed: format_qty(result.consumed),
                            unit:     ingredient.display_unit)
    end
  end

  private

  def set_recipe
    @recipe = current_household.recipes.find(params[:recipe_id])
  end

  def ingredient_params
    params.require(:recipe_ingredient).permit(:product_id, :quantity, :unit, :notes, :position)
  end

  # Trim trailing zeros so "2.000" reads as "2" in flashes.
  def format_qty(value)
    helpers.number_with_precision(value, precision: 3, strip_insignificant_zeros: true)
  end

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end
end
