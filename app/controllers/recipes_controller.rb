# frozen_string_literal: true
# typed: false

class RecipesController < ApplicationController
  before_action :ensure_household
  before_action :set_recipe, only: %i[show edit update destroy shop_missing]

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

  def edit
    pad_empty_ingredient_rows
  end

  def create
    @recipe = current_household.recipes.build(recipe_params)
    if @recipe.save
      redirect_to @recipe, notice: t("recipe.created", name: @recipe.name)
    else
      pad_empty_ingredient_rows
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @recipe.update(recipe_params)
      redirect_to @recipe, notice: t("recipe.updated", name: @recipe.name)
    else
      pad_empty_ingredient_rows
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    name = @recipe.name
    @recipe.destroy
    redirect_to recipes_path, notice: t("recipe.deleted", name: name)
  end

  # POST /recipes/import -- pulls a Chefkoch recipe by URL and turns
  # it into a local Recipe + RecipeIngredients (creating missing
  # Products on the fly).
  def import
    url = params[:url].to_s.strip
    if url.empty?
      redirect_to recipes_path, alert: t("recipe.import.url_required")
      return
    end

    result = Chefkoch::Importer.call(url: url, household: current_household)
    redirect_to result.recipe,
                notice: t("recipe.import.success",
                          name:        result.recipe.name,
                          ingredients: result.ingredients_created,
                          products:    result.products_created)
  rescue Chefkoch::Importer::ImportError => e
    redirect_to recipes_path, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to recipes_path,
                alert: t("recipe.import.invalid", error: e.record.errors.full_messages.to_sentence)
  end

  # POST /recipes/:id/shop_missing -- add every short-on-stock
  # ingredient (by exact deficit, not the full recipe amount) to the
  # household's grocery list. Rows already in storage in sufficient
  # quantity are skipped. Rows whose unit-override doesn't match the
  # product's storage unit are reported separately because we can't
  # compare on-hand against the recipe quantity safely.
  def shop_missing
    added       = 0
    bumped      = 0
    skipped     = 0
    unit_skips  = 0

    GroceryItem.transaction do
      @recipe.recipe_ingredients.includes(:product).each do |ing|
        # Unknown / mismatched units: can't compare on-hand vs recipe
        # quantity meaningfully; flag separately rather than silently
        # adding the wrong amount.
        unless ing.consumable?
          unit_skips += 1
          next
        end

        deficit = ing.quantity.to_d - ing.on_hand
        if deficit <= 0
          skipped += 1
          next
        end

        existing = current_household.grocery_items
                                    .find_by(product: ing.product, status: "needed")
        if existing
          existing.update!(quantity: existing.quantity + deficit)
          bumped += 1
        else
          current_household.grocery_items.create!(
            product:  ing.product,
            quantity: deficit,
            status:   "needed"
          )
          added += 1
        end
      end
    end

    redirect_to @recipe,
                notice: t("recipe.shop_missing.summary",
                          added:      added,
                          bumped:     bumped,
                          skipped:    skipped,
                          unit_skips: unit_skips)
  end

  private

  def set_recipe
    @recipe = current_household.recipes.find(params[:id])
  end

  def pad_empty_ingredient_rows
    return unless @recipe

    needed = 3 - @recipe.recipe_ingredients.select(&:new_record?).size
    needed.positive? && needed.times { @recipe.recipe_ingredients.build }
  end

  def recipe_params
    params.require(:recipe).permit(
      :name, :description, :servings, :prep_minutes, :cook_minutes, :notes, :tags,
      recipe_ingredients_attributes: %i[
        id product_id quantity unit notes position _destroy
      ]
    )
  end

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end
end
