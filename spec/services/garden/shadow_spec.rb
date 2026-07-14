# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Garden::Shadow do
  # 10 x 10 m footprint, corners at (0,0)..(10,10) in the drawing frame.
  let(:footprint) { [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]] }

  describe ".polygon" do
    it "casts north (up, -y) when the sun stands due south at 45 degrees" do
      shadow = described_class.polygon(footprint, azimuth_deg: 180, elevation_deg: 45, height_m: 10)
      # tan(45) = 1 -> offset exactly one building height northwards.
      expect(shadow.map(&:last).min).to be_within(0.05).of(-10.0)
      expect(shadow.map(&:last).max).to be_within(0.05).of(10.0)
      expect(shadow.map(&:first).minmax).to eq([0.0, 10.0]) # no east-west drift
    end

    it "casts west when the morning sun stands east" do
      shadow = described_class.polygon(footprint, azimuth_deg: 90, elevation_deg: 30, height_m: 5)
      length = 5 / Math.tan(30 * Math::PI / 180)
      expect(shadow.map(&:first).min).to be_within(0.05).of(-length)
      expect(shadow.map(&:last).minmax).to eq([0.0, 10.0]) # no north-south drift
    end

    it "returns a convex polygon containing base and offset (hull, no bowtie)" do
      shadow = described_class.polygon(footprint, azimuth_deg: 225, elevation_deg: 40, height_m: 8)
      # Hull of two offset squares has 6 corners, not 8.
      expect(shadow.length).to eq(6)
    end

    it "caps the shadow length for a sun just above the horizon" do
      shadow = described_class.polygon(footprint, azimuth_deg: 270, elevation_deg: 1.5, height_m: 10)
      expect(shadow.map(&:first).max).to be <= 10 + described_class::MAX_LENGTH_M + 0.1
    end

    it "returns nil when the sun is below the drawing threshold" do
      expect(described_class.polygon(footprint, azimuth_deg: 90, elevation_deg: 0.5, height_m: 10)).to be_nil
      expect(described_class.polygon(footprint, azimuth_deg: 90, elevation_deg: -5, height_m: 10)).to be_nil
    end

    it "returns nil for degenerate footprints" do
      expect(described_class.polygon(footprint.first(2), azimuth_deg: 180, elevation_deg: 45, height_m: 10)).to be_nil
      expect(described_class.polygon(nil, azimuth_deg: 180, elevation_deg: 45, height_m: 10)).to be_nil
    end
  end
end
