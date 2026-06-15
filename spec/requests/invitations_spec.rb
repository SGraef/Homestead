# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Invitations" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin) }

  describe "accepting an invite (public)" do
    let(:invitation) { Invitation.invite!(household: household, email: "newbie@example.com", role: "member") }
    let(:token)      { invitation.plaintext }

    it "shows the accept form for a valid token" do
      get invitation_path(token: token)
      expect(response).to have_http_status(:ok)
    end

    it "redirects an invalid/expired token to login" do
      get invitation_path(token: "bogus")
      expect(response).to redirect_to(login_path)
    end

    it "creates the account + membership and logs the user in" do
      patch invitation_path(token: token),
            params: { user: { name: "Newbie", password: "password123", password_confirmation: "password123" } }

      expect(response).to redirect_to(root_path)
      user = User.find_by(email: "newbie@example.com")
      expect(user).to be_present
      expect(user.activation_state).to eq("active")
      expect(household.users).to include(user)
    end

    it "re-renders (422) and creates no user on password mismatch" do
      patch invitation_path(token: token),
            params: { user: { name: "Newbie", password: "password123", password_confirmation: "nope" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(User.find_by(email: "newbie@example.com")).to be_nil
    end
  end

  describe "admin revoke" do
    before { login_via_post(admin) }

    it "revokes a pending invitation" do
      invitation = Invitation.invite!(household: household, email: "x@example.com", role: "member")

      expect { delete household_invitation_path(invitation) }
        .to change { household.invitations.pending.count }.by(-1)
      expect(response).to redirect_to(household_path)
    end
  end
end
