# frozen_string_literal: true
# typed: false

# Specialised view of the freezer slice of {StorageItem}, plus an inline
# quick-add form for homemade food (which doesn't need to live in the
# Products catalog up front -- the controller creates a "Homemade"
# Product on the fly so the existing storage / expiry / pricing model
# stays consistent).
class FreezerController < ApplicationController
  HOMEMADE_UNITS = %w[g portions l].freeze
  HOMEMADE_CATEGORY = "Homemade"

  before_action :ensure_household

  def show
    # Qualify columns -- `freezer_items` joins `locations` (also has its
    # own `created_at`), so a bare `created_at` is ambiguous to MySQL.
    scope = current_household.freezer_items
                             .order(Arel.sql(
                                      "COALESCE(storage_items.frozen_on, DATE(storage_items.created_at)) ASC"
                                    ))

    @query = params[:q].to_s.strip
    if @query.present?
      needle = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      scope  = scope.where("products.name LIKE :n OR products.brand LIKE :n", n: needle)
                    .references(:products)
    end

    @items = scope
    @stale = current_household.stale_freezer_items
    @stale_threshold_days = StorageItem::STALE_FREEZER_DAYS
  end

  # POST /freezer/homemade
  # Create a homemade product (auto-categorised) + a freezer storage item
  # in a single transaction.
  def homemade
    name = params[:name].to_s.strip
    unit = params[:unit].to_s
    quantity = params[:quantity]
    frozen_on = params[:frozen_on].presence || Date.current.to_s

    return redirect_to(freezer_path, alert: t("freezer.errors.name_required")) if name.empty?
    return redirect_to(freezer_path, alert: t("freezer.errors.bad_unit")) unless HOMEMADE_UNITS.include?(unit)

    StorageItem.transaction do
      product = current_household.products.create!(
        name:     name,
        unit:     unit,
        category: HOMEMADE_CATEGORY
      )
      current_household.storage_items.create!(
        product:   product,
        quantity:  quantity,
        location:  current_household.freezer_location,
        frozen_on: parse_date(frozen_on)
      )
    end

    redirect_to freezer_path, notice: t("freezer.added_homemade", name: name)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to freezer_path, alert: e.message
  end

  private

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    Date.current
  end
end
