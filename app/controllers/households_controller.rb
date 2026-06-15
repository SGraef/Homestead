# frozen_string_literal: true
# typed: false

# Settings page for the single household this instance serves. There is no
# index/create/switch/destroy: the one household is created at first-run sign-up
# (see {RegistrationsController}) and resolved everywhere via {Household.current}.
class HouseholdsController < ApplicationController
  before_action :set_household

  def show
    authorize @household
  end

  def edit
    authorize @household
  end

  def update
    authorize @household
    if @household.update(household_params)
      redirect_to household_path, notice: t("notices.household_updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_household
    @household = Household.current
    raise ActiveRecord::RecordNotFound unless @household
  end

  def household_params
    params.require(:household).permit(:name, :timezone, :postal_code, :flaschenpost_warehouse_id)
  end
end
