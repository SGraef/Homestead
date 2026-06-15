# frozen_string_literal: true
# typed: false

class ExpensesController < ApplicationController
  before_action :ensure_household

  def index
    months = (params[:months].presence || 6).to_i
    @report = ExpenseReport.new(household: current_household, months: months)
    @months = @report.months
  end

  private

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end
end
