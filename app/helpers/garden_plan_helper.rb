# frozen_string_literal: true
# typed: false

# SVG math for the server-rendered Grundstücksplan. All coordinates are in
# the local meter frame produced by Garden::Geometry.project_to_meters
# (x east, y south -- SVG-style, north is up).
module GardenPlanHelper
  # 8-wind compass index for a bearing in degrees (0 = first entry = north).
  # The names themselves are locale data (de: O for Ost, en: E for East).
  # @param bearing_deg [Float]
  # @return [String]
  def compass_point(bearing_deg)
    points = t("garden_map.plan.compass_points")
    points[(((bearing_deg + 22.5) / 45.0).floor % 8)]
  end

  # @param points [Array<Array(Float, Float)>]
  # @return [String] SVG path of the closed outline
  def plan_path(points)
    "#{points.map.with_index { |(x, y), i| "#{i.zero? ? "M" : "L"}#{x} #{y}" }.join(" ")} Z"
  end

  # @param points [Array<Array(Float, Float)>]
  # @return [Array(Float, Float)] width/height of the outline's bounding box
  def plan_extent(points)
    [points.map(&:first).max, points.map(&:last).max]
  end

  # Midpoint of each edge (closing edge included) -- anchor for its length label.
  # @param points [Array<Array(Float, Float)>]
  # @return [Array<Array(Float, Float)>]
  def plan_edge_midpoints(points)
    points.each_index.map do |i|
      x1, y1 = points[i]
      x2, y2 = points[(i + 1) % points.length]
      [(x1 + x2) / 2.0, (y1 + y2) / 2.0]
    end
  end

  # Drawing-frame centroid (vertex mean), anchor of the sun rays.
  # @param points [Array<Array(Float, Float)>]
  # @return [Array(Float, Float)]
  def plan_center(points)
    [points.sum(&:first) / points.length, points.sum(&:last) / points.length]
  end

  # Point at `radius` from `center` in compass direction `azimuth_deg`
  # (0 = north = -y on screen, 90 = east = +x; clockwise like the screen).
  # @return [Array(Float, Float)]
  def sun_point(center, azimuth_deg, radius)
    rad = azimuth_deg * Math::PI / 180.0
    [(center[0] + (radius * Math.sin(rad))).round(2),
     (center[1] - (radius * Math.cos(rad))).round(2)]
  end

  # Arc from the sunrise to the sunset azimuth the way the sun actually
  # travels (east over south to west = clockwise on a north-up plan).
  # @return [String] SVG path
  def sun_arc_path(center, sunrise_az, sunset_az, radius)
    from = sun_point(center, sunrise_az, radius)
    to   = sun_point(center, sunset_az, radius)
    large_arc = ((sunset_az - sunrise_az) % 360) > 180 ? 1 : 0
    "M#{from[0]} #{from[1]} A#{radius} #{radius} 0 #{large_arc} 1 #{to[0]} #{to[1]}"
  end
end
