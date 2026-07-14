# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Garden::Geometry do
  # A ~10m x 10m square at lat 52 deg (Niedersachsen): 10 m north-south is
  # ~8.983e-5 deg lat; 10 m east-west at that latitude is lng delta
  # 10 / (R * cos(52 deg)) in radians.
  let(:lat_step) { 10.0 / described_class::EARTH_RADIUS_M * 180 / Math::PI }
  let(:lng_step) { lat_step / Math.cos(52 * Math::PI / 180) }
  let(:square) do
    [{ "lat" => 52.0, "lng" => 9.0 },
     { "lat" => 52.0, "lng" => 9.0 + lng_step },
     { "lat" => 52.0 + lat_step, "lng" => 9.0 + lng_step },
     { "lat" => 52.0 + lat_step, "lng" => 9.0 }]
  end

  describe ".polygon_area_sqm" do
    it "measures a 10 m square within 0.5 percent" do
      expect(described_class.polygon_area_sqm(square)).to be_within(0.5).of(100.0)
    end

    it "is orientation-independent (clockwise ring)" do
      expect(described_class.polygon_area_sqm(square.reverse)).to be_within(0.5).of(100.0)
    end

    it "returns 0.0 for degenerate rings" do
      expect(described_class.polygon_area_sqm([])).to eq(0.0)
      expect(described_class.polygon_area_sqm(square.first(2))).to eq(0.0)
      expect(described_class.polygon_area_sqm(nil)).to eq(0.0)
    end

    it "accepts symbol keys" do
      ring = square.map { |p| { lat: p["lat"], lng: p["lng"] } }
      expect(described_class.polygon_area_sqm(ring)).to be_within(0.5).of(100.0)
    end
  end

  describe ".edge_lengths_m" do
    it "returns all four ~10 m edges including the closing one" do
      lengths = described_class.edge_lengths_m(square)
      expect(lengths.length).to eq(4)
      expect(lengths).to all(be_within(0.05).of(10.0))
    end

    it "returns [] for fewer than two points" do
      expect(described_class.edge_lengths_m([square.first])).to eq([])
    end
  end

  describe ".edge_bearings_deg" do
    it "walks the square east, north, west, south" do
      # Ring order: E along the south edge, N up the east edge, W along the
      # north edge, S down the west edge (closing).
      expect(described_class.edge_bearings_deg(square)).to eq([90.0, 0.0, 270.0, 180.0])
    end
  end

  describe "explicitly closed rings (GML style)" do
    it "collapses the repeated closing vertex instead of emitting a 0 m edge" do
      closed = square + [square.first]
      expect(described_class.edge_lengths_m(closed).length).to eq(4)
      expect(described_class.edge_lengths_m(closed)).to all(be_positive)
      expect(described_class.polygon_area_sqm(closed)).to be_within(0.5).of(100.0)
    end
  end

  describe ".project_to_meters" do
    it "anchors the bounding box at the origin with north up (y flipped)" do
      pts = described_class.project_to_meters(square)
      expect(pts.map(&:first).min).to eq(0.0)
      expect(pts.map(&:last).min).to eq(0.0)
      # First vertex is the SW corner geographically -> bottom-left on screen.
      expect(pts.first[0]).to eq(0.0)
      expect(pts.first[1]).to be_within(0.05).of(10.0)
      expect(pts.map(&:first).max).to be_within(0.05).of(10.0)
    end

    it "returns nil for degenerate input" do
      expect(described_class.project_to_meters(square.first(2))).to be_nil
      expect(described_class.project_to_meters(nil)).to be_nil
    end
  end

  describe ".centroid" do
    it "returns the vertex mean as [lat, lng]" do
      lat, lng = described_class.centroid(square)
      expect(lat).to be_within(1e-9).of(52.0 + (lat_step / 2))
      expect(lng).to be_within(1e-9).of(9.0 + (lng_step / 2))
    end

    it "returns nil for empty input" do
      expect(described_class.centroid([])).to be_nil
    end
  end
end
