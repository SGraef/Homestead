# frozen_string_literal: true
# typed: false

# The visual garden overview. `show` renders either the Leaflet map over
# official WMS layers or the abstract lite planner, per the household's
# {GardenMapSetting}; `update` is the admin-only settings form on that page.
# Bed geometry itself is saved via GardenBedsController#geometry.
class GardenMapsController < ApplicationController
  # Zoom used after an address jump: close enough to see the parcel.
  LOCATE_ZOOM = 18

  before_action :ensure_household
  before_action :set_settings

  def show
    authorize @settings, :show?
    @garden_beds = current_household.garden_beds.includes(plantings: :plant).ordered
  end

  def update
    authorize @settings
    if @settings.update(settings_params)
      redirect_to garden_map_path, notice: t("notices.garden_map_settings_saved")
    else
      @garden_beds = current_household.garden_beds.includes(plantings: :plant).ordered
      render :show, status: :unprocessable_content
    end
  end

  # The Grundstücksplan: the captured outline as a standalone to-scale map
  # with measurements, compass orientation and the sun's course (rise/set
  # directions and noon heights across the year, computed for the parcel's
  # own coordinates). Member-level like viewing the map.
  def plan
    authorize @settings, :show?
    return redirect_to(garden_map_path, alert: t("garden_map.plan.no_property")) unless @settings.property?

    ring            = @settings.property_boundary
    @points         = Garden::Geometry.project_to_meters(ring)
    @edge_lengths   = Garden::Geometry.edge_lengths_m(ring)
    @edge_bearings  = Garden::Geometry.edge_bearings_deg(ring)
    lat, lng        = Garden::Geometry.centroid(ring)
    zone            = ActiveSupport::TimeZone[current_household.timezone] || Time.zone
    @sun_days       = Garden::Sun.key_dates(Date.current.year).transform_values do |date|
      Garden::Sun.day(lat: lat, lng: lng, date: date, zone: zone)
    end
    @sun_now = Garden::Sun.position(lat: lat, lng: lng, time: Time.current)
  end

  # Address -> saved viewport, via server-side geocoding (Nominatim). Admin
  # like the rest of the settings; the geocoder is called at most once per
  # form submit.
  def locate
    authorize @settings, :update?
    result = Garden::Geocoder.search(params[:address])
    if result
      @settings.update(address: params[:address].to_s.strip.first(200),
                       center_lat: result.lat, center_lng: result.lng,
                       zoom: LOCATE_ZOOM)
      redirect_to garden_map_path, notice: t("garden_map.locate.found", place: result.display_name)
    else
      redirect_to garden_map_path, alert: t("garden_map.locate.not_found")
    end
  end

  # Saves (or clears, via an empty array) the Grundstück outline -- traced
  # on the map or adopted from the official parcel. Admin like the rest of
  # the settings; responds with the server-computed area.
  def property
    authorize @settings, :update?
    ring = Array(params[:property_boundary]).map do |point|
      point.permit(:lat, :lng).to_h if point.respond_to?(:permit)
    end
    if @settings.update(property_boundary: ring.compact.presence)
      render json: { property_area_sqm: @settings.property_area_sqm&.to_f }
    else
      render json: { errors: @settings.errors.full_messages }, status: :unprocessable_content
    end
  end

  # Point -> official parcel (Flurstück) outline + amtliche Fläche, proxied
  # server-side (the state WFS endpoints publish no CORS headers). Read-only
  # open data -> member-level like viewing the map.
  def parcel
    authorize @settings, :show?
    source = Garden::MapSources.parcel_source(@settings)
    head :unprocessable_content and return unless source

    parcel = Garden::ParcelLookup.at(lat: params[:lat].to_f, lng: params[:lng].to_f, source: source)
    if parcel
      render json: { boundary: parcel.boundary, area_sqm: parcel.area_sqm,
                     label: parcel.label, parcel_key: parcel.parcel_key }
    else
      head :not_found
    end
  end

  private

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end

  # Built in memory (not persisted) until the admin saves the form once, so
  # the map works out of the box with the Niedersachsen defaults.
  def set_settings
    @settings = current_household.garden_map_setting ||
                current_household.build_garden_map_setting
  end

  def settings_params
    params.require(:garden_map_setting).permit(
      :mode, :bundesland, :center_lat, :center_lng, :zoom,
      :custom_dop_url, :custom_dop_layer, :custom_alkis_url, :custom_alkis_layer
    )
  end
end
