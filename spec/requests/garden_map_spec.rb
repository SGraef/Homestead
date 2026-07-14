# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "GardenMap" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin) }

  describe "GET /garden_map" do
    before { login_via_post(admin) }

    it "renders map + planner with defaults (Niedersachsen, map mode) before any settings exist" do
      create(:garden_bed, household: household, name: "Raised bed A")
      get garden_map_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-controller=\"garden-map\"") # Grundstück capture
      expect(response.body).to include("data-controller=\"garden-lite\"") # planner below
      expect(response.body).to include("ni_dop20") # LGLN DOP layer in the client config
      expect(response.body).to include("Raised bed A")
    end

    it "renders only the planner in lite mode" do
      create(:garden_map_setting, household: household, mode: "lite")
      create(:garden_bed, household: household, width_m: 3, length_m: 1.2)
      get garden_map_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-controller=\"garden-lite\"")
      expect(response.body).not_to include("data-controller=\"garden-map\"")
    end
  end

  describe "PATCH /garden_map/property" do
    # Roughly 10 m x 10 m square near Hannover => ~100 m2.
    let(:ring) do
      step = 10.0 / Garden::Geometry::EARTH_RADIUS_M * 180 / Math::PI
      lng_step = step / Math.cos(52 * Math::PI / 180)
      [{ lat: 52.0, lng: 9.0 }, { lat: 52.0, lng: 9.0 + lng_step },
       { lat: 52.0 + step, lng: 9.0 + lng_step }, { lat: 52.0 + step, lng: 9.0 }]
    end

    it "saves the Grundstück outline and returns the computed area (admin)" do
      login_via_post(admin)
      patch property_garden_map_path, params: { property_boundary: ring }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["property_area_sqm"]).to be_within(1).of(100)
      expect(household.reload.garden_map_setting.property_boundary.length).to eq(4)
    end

    it "clears the outline with an empty array" do
      login_via_post(admin)
      create(:garden_map_setting, household:         household,
                                  property_boundary: ring.map { |p| p.transform_keys(&:to_s) })
      patch property_garden_map_path, params: { property_boundary: [] }, as: :json
      expect(response).to have_http_status(:ok)
      settings = household.reload.garden_map_setting
      expect(settings.property_boundary).to be_nil
      expect(settings.property_area_sqm).to be_nil
    end

    it "rejects malformed rings" do
      login_via_post(admin)
      patch property_garden_map_path,
            params: { property_boundary: [{ lat: 999, lng: 9 }, { lat: 52, lng: 9 }, { lat: 52, lng: 10 }] },
            as:     :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "denies non-admin members" do
      member = create(:user)
      create(:membership, user: member, household: household)
      login_via_post(member)
      patch property_garden_map_path, params: { property_boundary: ring }, as: :json
      expect(household.reload.garden_map_setting&.property_boundary).to be_nil
    end
  end

  describe "PATCH /garden_map" do
    context "when signed in as an admin" do
      before { login_via_post(admin) }

      it "creates the settings record on first save" do
        expect do
          patch garden_map_path, params: { garden_map_setting: {
            mode: "map", bundesland: "ni", center_lat: 52.37, center_lng: 9.73, zoom: 18
          } }
        end.to change(GardenMapSetting, :count).by(1)
        expect(response).to redirect_to(garden_map_path)
        expect(household.reload.garden_map_setting.zoom).to eq(18)
      end

      it "rejects a non-http custom WMS URL" do
        patch garden_map_path, params: { garden_map_setting: {
          bundesland: "custom", custom_dop_url: "javascript:alert(1)", custom_dop_layer: "x"
        } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(GardenMapSetting.count).to eq(0)
      end
    end

    context "when using the address lookup" do
      before { login_via_post(admin) }

      it "geocodes and saves the viewport" do
        stub_request(:get, %r{nominatim\.openstreetmap\.org/search}).to_return(
          status: 200,
          body:   [{ lat: "52.3705", lon: "9.7332", display_name: "Hannover" }].to_json
        )
        post locate_garden_map_path, params: { address: "Hannah-Arendt-Platz 1, Hannover" }
        expect(response).to redirect_to(garden_map_path)
        settings = household.reload.garden_map_setting
        expect(settings.center_lat.to_f).to eq(52.3705)
        expect(settings.zoom).to eq(GardenMapsController::LOCATE_ZOOM)
        expect(settings.address).to include("Hannah-Arendt-Platz")
      end

      it "reports an unresolvable address without saving" do
        stub_request(:get, %r{nominatim\.openstreetmap\.org/search}).to_return(status: 200, body: "[]")
        post locate_garden_map_path, params: { address: "Nowhere 99" }
        expect(response).to redirect_to(garden_map_path)
        expect(flash[:alert]).to eq(I18n.t("garden_map.locate.not_found"))
      end
    end

    context "when signed in as a non-admin member" do
      let(:member) { create(:user) }

      before do
        create(:membership, user: member, household: household)
        login_via_post(member)
      end

      it "can view the map but not change settings" do
        get garden_map_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(I18n.t("garden_map.settings.heading"))

        patch garden_map_path, params: { garden_map_setting: { mode: "lite" } }
        expect(response).to redirect_to(root_path) # Pundit denial
        expect(GardenMapSetting.count).to eq(0)
      end

      it "cannot use the address lookup" do
        post locate_garden_map_path, params: { address: "Hannover" }
        expect(response).to redirect_to(root_path) # Pundit denial
      end
    end
  end

  describe "GET /garden_map/plan" do
    # ~10 m x 10 m square near Hannover (see the property PATCH spec above).
    let(:ring) do
      step = 10.0 / Garden::Geometry::EARTH_RADIUS_M * 180 / Math::PI
      lng_step = step / Math.cos(52 * Math::PI / 180)
      [{ "lat" => 52.0, "lng" => 9.0 }, { "lat" => 52.0, "lng" => 9.0 + lng_step },
       { "lat" => 52.0 + step, "lng" => 9.0 + lng_step }, { "lat" => 52.0 + step, "lng" => 9.0 }]
    end

    before { login_via_post(admin) }

    it "renders the plan with sun course, north arrow and edge table (member-level)" do
      create(:garden_map_setting, household: household, property_boundary: ring)
      get plan_garden_map_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("garden-plan-svg")
      expect(response.body).to include("sun--summer-solstice")
      expect(response.body).to include("sun--winter-solstice")
      expect(response.body).to include(CGI.escapeHTML(I18n.t("garden_map.plan.edges_heading")))
      expect(response.body).to include(I18n.t("garden_map.plan.days.summer_solstice"))
      # 10 m edge label from the outline
      expect(response.body).to match(/10[.,]0 m/)
    end

    it "redirects to the garden map when no property has been captured" do
      get plan_garden_map_path
      expect(response).to redirect_to(garden_map_path)
      expect(flash[:alert]).to eq(I18n.t("garden_map.plan.no_property"))
    end

    context "with buildings on the property" do
      before do
        household.update!(timezone: "Europe/Berlin") # fixed local clock for the shadow hours
        create(:garden_map_setting, household: household, property_boundary: ring)
        create(:garden_structure, household: household, name: "Haus", height_m: 6.5)
      end

      it "draws the building and its shadows for the default day (today)" do
        get plan_garden_map_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("class=\"structure\"")
        expect(response.body).to include("Haus")
        expect(response.body).to include("class=\"shadow\"")
        expect(response.body).to include(I18n.t("garden_map.plan.days.today"))
      end

      it "casts long shadows at the winter solstice via ?day=" do
        get plan_garden_map_path(day: "winter_solstice")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("class=\"shadow\"")
        # 18:00 winter sun is below the horizon, so only earlier layers render.
        expect(response.body).to include(I18n.t("garden_map.plan.shadow_legend",
                                                date:  I18n.l(Date.new(Date.current.year, 12, 21),
                                                              format: :short),
                                                hours: "9, 12, 15"))
      end

      it "falls back to today for an unknown day param" do
        get plan_garden_map_path(day: "junk")
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /garden_map/parcel" do
    let(:gml) { Rails.root.join("spec/fixtures/garden/alkis_flurstueck.xml").read }

    before { login_via_post(admin) }

    it "returns the official parcel at a point as JSON (member-level)" do
      stub_request(:get, /opendata\.lgln\.niedersachsen\.de/).to_return(status: 200, body: gml)
      get parcel_garden_map_path, params: { lat: 52.3705, lng: 9.7332 }
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["area_sqm"]).to eq(13_452.0)
      expect(body["boundary"].length).to eq(4)
      expect(body["label"]).to eq("Hannah-Arendt-Platz 1")
    end

    it "404s when no parcel is found" do
      stub_request(:get, /opendata\.lgln\.niedersachsen\.de/).to_return(status: 502)
      get parcel_garden_map_path, params: { lat: 52.3705, lng: 9.7332 }
      expect(response).to have_http_status(:not_found)
    end

    it "422s when the Bundesland has no parcel source" do
      create(:garden_map_setting, household: household, bundesland: "nw")
      get parcel_garden_map_path, params: { lat: 52.3705, lng: 9.7332 }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
