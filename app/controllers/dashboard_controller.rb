# frozen_string_literal: true
# typed: true

class DashboardController < ApplicationController
  def index
    @household       = current_household
    @expiring        = @household&.expiring_storage(days: 7) || []
    @open_groceries  = @household&.open_grocery_items || []
    @recent_products = @household&.products&.order(created_at: :desc)&.limit(8) || []
    @this_month      = @household && ExpenseReport.new(household: @household, months: 1).current_month
    @stale_freezer   = @household&.stale_freezer_items || []
  end
end
