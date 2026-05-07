# frozen_string_literal: true
# typed: true

class HouseholdsController < ApplicationController
  before_action :set_household, only: %i[show edit update destroy]

  def index
    @households = current_user.households
  end

  def show
    authorize @household
  end

  def new
    @household = Household.new
    authorize @household
  end

  def create
    @household = Household.new(household_params)
    authorize @household
    if @household.save
      Membership.create!(user: current_user, household: @household, role: "admin")
      session[:household_id] = @household.id
      redirect_to @household, notice: t("notices.household_created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @household
  end

  def update
    authorize @household
    if @household.update(household_params)
      redirect_to @household, notice: t("notices.household_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @household
    @household.destroy
    redirect_to households_path, notice: t("notices.household_removed")
  end

  private

  def set_household
    @household = current_user.households.find(params[:id])
  end

  def household_params
    params.require(:household).permit(:name, :timezone)
  end
end
