# frozen_string_literal: true
# typed: false

# Buildings on the Grundstück (house, garage, ...): traced on the garden map
# like the property outline, then named and given a height in the list below
# the map. Admin-only (structures are captured reality, like the outline);
# members see them on the planner and the Grundstücksplan.
class GardenStructuresController < ApplicationController
  DEFAULT_HEIGHT_M = 6.0

  before_action :ensure_household

  # JSON endpoint for the map's tracing flow: receives the ring, creates the
  # structure with a placeholder name so the admin can rename it in the list.
  def create
    structure = current_household.garden_structures.new(
      name:     t("garden_structure.default_name", number: current_household.garden_structures.count + 1),
      kind:     "other",
      height_m: DEFAULT_HEIGHT_M,
      boundary: boundary_param
    )
    authorize structure

    if structure.save
      render json: { id: structure.id }, status: :created
    else
      render json: { errors: structure.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    structure = current_household.garden_structures.find(params[:id])
    authorize structure

    if structure.update(structure_params)
      redirect_to garden_map_path, notice: t("garden_structure.saved")
    else
      redirect_to garden_map_path, alert: structure.errors.full_messages.to_sentence
    end
  end

  def destroy
    structure = current_household.garden_structures.find(params[:id])
    authorize structure
    structure.destroy
    redirect_to garden_map_path, notice: t("garden_structure.deleted")
  end

  private

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end

  def boundary_param
    Array(params[:boundary]).map do |point|
      point.permit(:lat, :lng).to_h if point.respond_to?(:permit)
    end.compact
  end

  def structure_params
    params.require(:garden_structure).permit(:name, :kind, :height_m)
  end
end
