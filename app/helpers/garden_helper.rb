# frozen_string_literal: true
# typed: false

module GardenHelper
  # Render a month window (1-12) as localized abbreviated names, e.g. "Mar–Apr".
  # A single month renders alone; nil bounds render an em dash.
  # @return [String]
  def garden_month_range(from, to)
    return "—" if from.blank? || to.blank?

    names = I18n.t("date.abbr_month_names")
    from == to ? names[from] : "#{names[from]}–#{names[to]}"
  end

  # Localized crop label for a companion key (falls back to the humanized key).
  # @return [String]
  def garden_crop_label(key)
    t("garden.crops.#{key}", default: key.to_s.humanize)
  end

  # Label for the one-tap "advance" button given a planting's current status,
  # or nil once harvested (nothing left to advance to).
  # @return [String, nil]
  def planting_advance_label(planting)
    case planting.status
    when "planned" then t("planting.advance.to_sown")
    when "sown"    then t("planting.advance.to_growing")
    when "growing" then t("planting.advance.to_harvested")
    end
  end

  # Bed payload for the garden planner Stimulus controller. Uses the
  # preloaded plantings (no per-bed queries) and ships each bed's save URL
  # so the JS never templates routes.
  # @param beds [Enumerable<GardenBed>] with plantings+plants preloaded
  # @return [Array<Hash>]
  def garden_map_beds_json(beds)
    beds.map do |bed|
      active = bed.plantings.reject { |p| p.status == "harvested" }
      { id: bed.id, name: bed.name,
        url: garden_bed_path(bed), geometryUrl: geometry_garden_bed_path(bed),
        widthM: bed.width_m&.to_f, lengthM: bed.length_m&.to_f,
        posXM: bed.pos_x_m&.to_f, posYM: bed.pos_y_m&.to_f,
        areaSqm: bed.area_sqm&.to_f,
        plantings: active.map { |p| p.plant.name } }
    end
  end

  # Structure payload for the map (rendering + tracing) and the lite planner
  # (fixed obstacles).
  # @param structures [Enumerable<GardenStructure>]
  # @return [Array<Hash>]
  def garden_map_structures_json(structures)
    structures.map do |structure|
      { id: structure.id, name: structure.name, boundary: structure.boundary }
    end
  end

  # Pixel width of the planner's aerial underlay (DOP20 is 20 cm/px, so this
  # is sharper than the source for any garden-sized parcel).
  PLANNER_PHOTO_WIDTH_PX = 1200

  # Aerial-photo underlay for the parcel planner: one WMS GetMap request
  # covering the Grundstück bounding box plus the planner margin. Requested in
  # EPSG:4326, which is linear in lat/lng per axis -- exactly like the
  # planner's equirectangular frame -- so the image aligns with the drawn
  # geometry by construction (WMS 1.3.0: BBOX axis order is lat,lng).
  # @param settings [GardenMapSetting]
  # @return [Hash, nil] { url:, x:, y:, width:, height: } in frame meters
  def garden_planner_photo(settings)
    return nil unless settings.map_mode? && settings.property?

    dop = Garden::MapSources.client_config(settings)[:dop]
    points = dop && Garden::Geometry.project_to_meters(settings.property_boundary)
    return nil unless points

    width_m  = points.map(&:first).max
    height_m = points.map(&:last).max
    margin_m = 1.0 # mirrors MARGIN_M in the planner JS
    lats = settings.property_boundary.pluck("lat")
    lngs = settings.property_boundary.pluck("lng")
    dlat = margin_m / Garden::Geometry::EARTH_RADIUS_M * 180 / Math::PI
    dlng = dlat / Math.cos(lats.sum / lats.length * Math::PI / 180)

    query = {
      "SERVICE" => "WMS", "REQUEST" => "GetMap", "VERSION" => "1.3.0",
      "LAYERS" => dop[:layer], "STYLES" => "", "CRS" => "EPSG:4326",
      "BBOX"   => [lats.min - dlat, lngs.min - dlng, lats.max + dlat, lngs.max + dlng].join(","),
      "WIDTH"  => PLANNER_PHOTO_WIDTH_PX,
      "HEIGHT" => ((height_m + (2 * margin_m)) / (width_m + (2 * margin_m)) *
                   PLANNER_PHOTO_WIDTH_PX).round,
      "FORMAT" => "image/jpeg"
    }
    { url:    "#{dop[:url]}#{dop[:url].include?("?") ? "&" : "?"}#{query.to_query}",
      x:      -margin_m, y: -margin_m,
      width:  (width_m + (2 * margin_m)).round(2),
      height: (height_m + (2 * margin_m)).round(2) }
  end

  # Bad-neighbour conflicts within a bed: for each active planting, the other
  # crop keys present that its companion table warns against.
  # @param plantings [Enumerable<Planting>]
  # @return [Hash{Planting=>Array<String>}] only plantings with a conflict.
  def companion_conflicts_for(plantings)
    active = plantings.reject { |p| p.status == "harvested" }
    present = active.map(&:crop_key).compact
    active.each_with_object({}) do |planting, out|
      next if planting.crop_key.blank?

      bad = (planting.plant&.companions&.dig(:bad) || []) & present
      out[planting] = bad if bad.any?
    end
  end
end
