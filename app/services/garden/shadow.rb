# frozen_string_literal: true
# typed: false

module Garden
  # Ground shadow of a building for a given sun position, in the plan's
  # drawing frame (meters, x east, y south -- north is up on screen).
  #
  # Model: the building is a prism (flat footprint extruded to height_m).
  # Every roof vertex casts to base vertex + L * away-from-sun, with
  # L = height / tan(elevation). The ground shadow of the whole prism is the
  # convex hull of the base and the offset base -- exact for convex
  # footprints, a slight over-cover for concave ones (fine for "where can a
  # bed still get light" purposes).
  module Shadow
    # Below this sun elevation shadows are effectively infinite and the tan
    # blows up; the sun also barely counts as light. No shadow is drawn.
    MIN_ELEVATION_DEG = 1.0

    # Cap the shadow length so a sunrise sun cannot paint a kilometer-long
    # polygon over the plan (100 m is far beyond any Grundstück drawing).
    MAX_LENGTH_M = 100.0

    class << self
      # @param points [Array<Array(Float, Float)>] footprint in the drawing frame
      # @param azimuth_deg [Float] sun compass azimuth (0 = N, 90 = E)
      # @param elevation_deg [Float] sun height above the horizon
      # @param height_m [Float] building height
      # @return [Array<Array(Float, Float)>, nil] shadow polygon, nil when the
      #   sun is down/too low or the footprint degenerate
      def polygon(points, azimuth_deg:, elevation_deg:, height_m:)
        return nil if points.nil? || points.length < 3
        return nil if elevation_deg < MIN_ELEVATION_DEG

        length = [height_m / Math.tan(elevation_deg * Math::PI / 180.0), MAX_LENGTH_M].min
        # Shadow falls away from the sun: azimuth + 180. On screen (y down),
        # a compass direction t maps to (sin t, -cos t).
        away = (azimuth_deg + 180.0) * Math::PI / 180.0
        dx = length * Math.sin(away)
        dy = -length * Math.cos(away)

        shifted = points.map { |x, y| [(x + dx).round(2), (y + dy).round(2)] }
        convex_hull(points + shifted)
      end

      private

      # Andrew's monotone chain, counter-clockwise hull in screen coordinates.
      def convex_hull(points)
        pts = points.map { |x, y| [x.to_f, y.to_f] }.uniq.sort
        return pts if pts.length <= 2

        lower = chain(pts)
        upper = chain(pts.reverse)
        lower[0...-1] + upper[0...-1]
      end

      def chain(pts)
        hull = []
        pts.each do |p|
          hull.pop while hull.length >= 2 && cross(hull[-2], hull[-1], p) <= 0
          hull << p
        end
        hull
      end

      def cross(origin, a, b)
        ((a[0] - origin[0]) * (b[1] - origin[1])) -
          ((a[1] - origin[1]) * (b[0] - origin[0]))
      end
    end
  end
end
