# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe GardenStructure do
  subject(:structure) { build(:garden_structure) }

  it "is valid with the factory defaults" do
    expect(structure).to be_valid
  end

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_inclusion_of(:kind).in_array(GardenStructure::KINDS) }

  it "rejects heights outside the sane range" do
    expect(build(:garden_structure, height_m: 0.2)).not_to be_valid
    expect(build(:garden_structure, height_m: 80)).not_to be_valid
  end

  it "rejects malformed boundaries" do
    expect(build(:garden_structure, boundary: nil)).not_to be_valid
    expect(build(:garden_structure, boundary: [{ "lat" => 52.0, "lng" => 9.0 }])).not_to be_valid
    expect(build(:garden_structure, boundary: [{ "lat" => 999, "lng" => 9.0 }] * 3)).not_to be_valid
  end

  it "computes the footprint area from the ring" do
    expect(structure.area_sqm).to be_within(1).of(80) # 10 m x 8 m factory footprint
  end
end
