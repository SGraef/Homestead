# frozen_string_literal: true
# typed: false

class LocationsController < ApplicationController
  before_action :ensure_household
  before_action :set_location, only: %i[edit update destroy]

  def index
    @locations = current_household.locations.ordered
    @counts    = current_household.storage_items.group(:location_id).count
    @counts.default = 0
  end

  def new
    @location = current_household.locations.build(kind: "other")
    authorize @location
  end

  def edit
    authorize @location
  end

  def create
    @location = current_household.locations.build(location_params)
    authorize @location
    if @location.save
      redirect_to locations_path, notice: t("notices.location_added")
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    authorize @location
    if @location.update(location_params)
      redirect_to locations_path, notice: t("notices.location_updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @location
    if @location.storage_items.exists?
      redirect_to locations_path, alert: t("notices.location_has_items")
    else
      @location.destroy
      redirect_to locations_path, notice: t("notices.location_removed")
    end
  end

  private

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_location
    @location = current_household.locations.find(params[:id])
  end

  def location_params
    params.require(:location).permit(:name, :kind, :position)
  end
end
