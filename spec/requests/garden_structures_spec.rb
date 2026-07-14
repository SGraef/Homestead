# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "GardenStructures" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin) }

  let(:ring) do
    lat_step = 8.0 / Garden::Geometry::EARTH_RADIUS_M * 180 / Math::PI
    [{ lat: 52.0, lng: 9.0 }, { lat: 52.0, lng: 9.0001 },
     { lat: 52.0 + lat_step, lng: 9.0001 }, { lat: 52.0 + lat_step, lng: 9.0 }]
  end

  describe "as an admin" do
    before { login_via_post(admin) }

    it "creates a structure from a traced ring with a default name and height" do
      expect do
        post garden_structures_path, params: { boundary: ring }, as: :json
      end.to change(household.garden_structures, :count).by(1)
      expect(response).to have_http_status(:created)

      structure = household.garden_structures.last
      expect(structure.name).to eq(I18n.t("garden_structure.default_name", number: 1))
      expect(structure.kind).to eq("other")
      expect(structure.height_m.to_f).to eq(GardenStructuresController::DEFAULT_HEIGHT_M)
      expect(structure.boundary.length).to eq(4)
    end

    it "rejects a degenerate ring" do
      post garden_structures_path, params: { boundary: ring.first(2) }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(GardenStructure.count).to eq(0)
    end

    it "updates name, kind and height from the list form" do
      structure = create(:garden_structure, household: household)
      patch garden_structure_path(structure), params: {
        garden_structure: { name: "Garage", kind: "garage", height_m: 3.2 }
      }
      expect(response).to redirect_to(garden_map_path)
      expect(structure.reload).to have_attributes(name: "Garage", kind: "garage")
      expect(structure.height_m.to_f).to eq(3.2)
    end

    it "removes a structure" do
      structure = create(:garden_structure, household: household)
      expect { delete garden_structure_path(structure) }
        .to change(GardenStructure, :count).by(-1)
    end
  end

  describe "as a non-admin member" do
    let(:member) { create(:user) }

    before do
      create(:membership, user: member, household: household)
      login_via_post(member)
    end

    it "cannot create structures" do
      post garden_structures_path, params: { boundary: ring }, as: :json
      expect(GardenStructure.count).to eq(0)
    end

    it "cannot update or delete structures" do
      structure = create(:garden_structure, household: household)
      patch garden_structure_path(structure), params: { garden_structure: { name: "X" } }
      expect(structure.reload.name).not_to eq("X")

      delete garden_structure_path(structure)
      expect(GardenStructure.count).to eq(1)
    end
  end
end
