# frozen_string_literal: true

FactoryBot.define do
  factory :garden_structure do
    household
    sequence(:name) { |n| "Gebäude #{n}" }
    kind     { "house" }
    height_m { 6.5 }
    # ~10 m x 8 m footprint near Hannover.
    boundary do
      lat_step = 8.0 / Garden::Geometry::EARTH_RADIUS_M * 180 / Math::PI
      lng_step = (10.0 / Garden::Geometry::EARTH_RADIUS_M * 180 / Math::PI) /
                 Math.cos(52 * Math::PI / 180)
      [{ "lat" => 52.0001, "lng" => 9.0001 },
       { "lat" => 52.0001, "lng" => 9.0001 + lng_step },
       { "lat" => 52.0001 + lat_step, "lng" => 9.0001 + lng_step },
       { "lat" => 52.0001 + lat_step, "lng" => 9.0001 }]
    end
  end
end
