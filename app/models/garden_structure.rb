# frozen_string_literal: true
# typed: false

# A building on the Grundstück -- house, garage, shed... -- captured the same
# way as the property itself: traced on the official imagery (lat/lng ring).
# The height turns the footprint into a light blocker: the Grundstücksplan
# projects each structure's shadow for chosen sun positions, so beds can be
# placed where they actually get light. Fixed reality like the property
# outline, so admin-managed; beds (the plans) stay in the planner.
class GardenStructure < ApplicationRecord
  KINDS = %w[house garage shed greenhouse other].freeze

  # Buildings are simple footprints; official building outlines rarely have
  # more than a few dozen vertices.
  MAX_VERTICES = 200

  # Sanity range in meters: garden wall to apartment block.
  HEIGHT_RANGE = (0.5..50.0)

  belongs_to :household

  validates :name, presence: true, length: { maximum: 80 }
  validates :kind, inclusion: { in: KINDS }
  validates :height_m, presence:     true,
                       numericality: { in: HEIGHT_RANGE }
  validate  :boundary_shape

  scope :ordered, -> { order(:created_at) }

  # @return [Float] footprint area in square meters
  def area_sqm
    Garden::Geometry.polygon_area_sqm(boundary)
  end

  private

  # Same shape rule as GardenMapSetting#property_boundary_shape: an array of
  # 3..MAX_VERTICES {lat:, lng:} hashes within WGS84 range.
  def boundary_shape
    return errors.add(:boundary, :invalid) unless boundary.is_a?(Array) &&
                                                  boundary.length.between?(3, MAX_VERTICES)

    valid = boundary.all? do |point|
      point.is_a?(Hash) &&
        point["lat"].is_a?(Numeric) && point["lat"].between?(-90, 90) &&
        point["lng"].is_a?(Numeric) && point["lng"].between?(-180, 180)
    end
    errors.add(:boundary, :invalid) unless valid
  end
end
