# frozen_string_literal: true
# typed: true

# Add / remove individual keywords inside an {OfferCategory}. Scoped
# through the household to keep cross-tenant lookups impossible.
class OfferCategoryKeywordsController < ApplicationController
  before_action :ensure_household
  before_action :set_category

  def create
    keyword = @category.offer_category_keywords.new(keyword_params)
    if keyword.save
      redirect_to offer_categories_path,
                  notice: t("offer.categories.flash.keyword_added",
                            keyword: keyword.keyword, category: @category.name)
    else
      redirect_to offer_categories_path,
                  alert: keyword.errors.full_messages.to_sentence
    end
  end

  def destroy
    keyword = @category.offer_category_keywords.find(params[:id])
    keyword.destroy
    redirect_to offer_categories_path,
                notice: t("offer.categories.flash.keyword_removed",
                          keyword: keyword.keyword, category: @category.name)
  end

  private

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_category
    @category = current_household.offer_categories.find(params[:offer_category_id])
  end

  def keyword_params
    params.require(:offer_category_keyword).permit(:keyword)
  end
end
