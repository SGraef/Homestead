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
