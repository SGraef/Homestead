# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Household settings" do
  let(:admin)  { create(:user) }
  let!(:household) { create(:household, admin: admin) }

  describe "as an admin" do
    before { login_via_post(admin) }

    it "shows the settings page" do
      get household_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(household.name)
    end

    it "updates the household" do
      patch household_path, params: { household: { name: "Renamed", timezone: "Europe/Berlin" } }
      expect(response).to redirect_to(household_path)
      expect(household.reload.name).to eq("Renamed")
    end

    it "adds an existing user as a member by email" do
      newcomer = create(:user, email: "newcomer@example.com")
      expect { post household_memberships_path, params: { membership: { email: newcomer.email, role: "member" } } }
        .to change { household.reload.memberships.count }.by(1)
      expect(household.users).to include(newcomer)
    end
  end

  describe "as a non-admin member" do
    let(:member) { create(:user) }

    before do
      Membership.create!(user: member, household: household, role: "member")
      login_via_post(member)
    end

    it "can view settings" do
      get household_path
      expect(response).to have_http_status(:ok)
    end

    it "cannot update the household" do
      patch household_path, params: { household: { name: "Hacked" } }
      expect(response).to redirect_to(root_path)
      expect(household.reload.name).not_to eq("Hacked")
    end
  end
end
