# frozen_string_literal: true
# typed: false

# CRUD for the household's offer-category mapping that drives
# {OfferCategorizer}. The index page is a one-stop edit surface:
# list, add, rename, reorder by position, delete, plus a "Reset to
# defaults" button that re-seeds from `config/offer_categories.yml`.
class OfferCategoriesController < ApplicationController
  before_action :ensure_household
  before_action :set_category, only: %i[update destroy]

  def index
    @categories = current_household.offer_categories.ordered.includes(:offer_category_keywords)
    @new_category = current_household.offer_categories.new(position: next_position)
  end

  def create
    @category = current_household.offer_categories.new(category_params)
    @category.position = next_position if @category.position.to_i.zero?

    if @category.save
      redirect_to offer_categories_path,
                  notice: t("offer.categories.flash.created", name: @category.name)
    else
      flash.now[:alert] = @category.errors.full_messages.to_sentence
      @categories = current_household.offer_categories.ordered.includes(:offer_category_keywords)
      @new_category = @category
      render :index, status: :unprocessable_content
    end
  end

  def update
    if @category.update(category_params)
      redirect_to offer_categories_path,
                  notice: t("offer.categories.flash.updated", name: @category.name)
    else
      redirect_to offer_categories_path,
                  alert: @category.errors.full_messages.to_sentence
    end
  end

  def destroy
    @category.destroy
    redirect_to offer_categories_path,
                notice: t("offer.categories.flash.removed", name: @category.name)
  end

  # POST /offers/categories/reset_defaults
  # Wipes the household's categories + keywords and re-seeds from the
  # YAML factory baseline. Guarded with a turbo-confirm in the view.
  def reset_defaults
    n = OfferCategorySeeder.call(current_household, replace: true)
    redirect_to offer_categories_path,
                notice: t("offer.categories.flash.reset_done", count: n)
  end

  private

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_category
    @category = current_household.offer_categories.find(params[:id])
  end

  def category_params
    params.require(:offer_category).permit(:name, :position)
  end

  # Next position for a brand-new entry — append at the end with the
  # same gap-of-10 scheme the seeder uses.
  def next_position
    (current_household.offer_categories.maximum(:position) || 0) + 10
  end
end
