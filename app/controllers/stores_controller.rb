# frozen_string_literal: true
# typed: false

class StoresController < ApplicationController
  before_action :ensure_household
  before_action :set_store, only: %i[show edit update destroy]

  def index
    @stores = policy_scope(current_household.stores).order(:name)
  end

  def show
    authorize @store
    @recent_prices = @store.prices.includes(:product).recent.limit(50)
  end

  def new
    @store = current_household.stores.build
    authorize @store
  end

  def edit
    authorize @store
  end

  def create
    @store = current_household.stores.build(store_params)
    authorize @store
    if @store.save
      redirect_to @store, notice: t("notices.store_added")
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    authorize @store
    if @store.update(store_params)
      redirect_to @store, notice: t("notices.store_updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @store
    @store.destroy
    redirect_to stores_path, notice: t("notices.store_removed")
  end

  private

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_store
    @store = current_household.stores.find(params[:id])
  end

  def store_params
    params.require(:store).permit(:name, :chain, :address, :url)
  end
end
