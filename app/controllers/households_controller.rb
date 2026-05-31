# frozen_string_literal: true
# typed: false

class HouseholdsController < ApplicationController
  before_action :set_household, only: %i[show edit update destroy switch leave]

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

  def edit
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
      render :new, status: :unprocessable_content
    end
  end

  def update
    authorize @household
    if @household.update(household_params)
      redirect_to @household, notice: t("notices.household_updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @household
    @household.destroy
    session[:household_id] = nil if session[:household_id] == @household.id
    redirect_to households_path, notice: t("notices.household_removed")
  end

  # POST /households/:id/switch — set the active household for the session.
  # Any member of the household can call this.
  def switch
    authorize @household, :show?
    session[:household_id] = @household.id
    redirect_to root_path,
                notice: t("notices.household_switched", name: @household.name)
  end

  # DELETE /households/:id/leave — current_user removes their own membership.
  # Refuses to leave if the user is the household's last admin (would
  # orphan everything else).
  def leave
    authorize @household, :show?
    membership = @household.memberships.find_by!(user_id: current_user.id)

    if membership.role == "admin" && @household.memberships.where(role: "admin").count <= 1
      redirect_to @household, alert: t("notices.last_admin_cannot_leave")
      return
    end

    membership.destroy
    session[:household_id] = nil if session[:household_id] == @household.id
    redirect_to households_path, notice: t("notices.household_left", name: @household.name)
  end

  private

  def set_household
    @household = current_user.households.find(params[:id])
  end

  def household_params
    params.require(:household).permit(:name, :timezone, :postal_code, :flaschenpost_warehouse_id)
  end
end
