# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Registrations" do
  let(:valid_params) do
    { user: { email: "first@example.com", name: "First", password: "password123", password_confirmation: "password123" } }
  end

  describe "first run (empty instance)" do
    it "shows the sign-up form" do
      get new_registration_path
      expect(response).to have_http_status(:ok)
    end

    it "creates the user, the single household, and an admin membership" do
      expect { post registration_path, params: valid_params }
        .to change(User, :count).by(1)
        .and change(Household, :count).by(1)
        .and change(Membership, :count).by(1)

      household = Household.current
      user      = User.find_by(email: "first@example.com")
      expect(household).to be_present
      expect(user.admin_of?(household)).to be true
      expect(response).to redirect_to(login_path)
    end
  end

  describe "after the instance is set up" do
    let(:user) { create(:user) }

    before { create(:household, admin: user) }

    it "closes the sign-up form" do
      get new_registration_path
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq(I18n.t("auth.registration_closed"))
    end

    it "refuses to create a second user or household" do
      expect { post registration_path, params: valid_params }
        .not_to change(User, :count)
      expect(Household.count).to eq(1)
      expect(User.find_by(email: "first@example.com")).to be_nil
      expect(response).to redirect_to(login_path)
    end
  end
end
