# frozen_string_literal: true
# typed: false

require "rails_helper"

# Login behaviour for LDAP-linked accounts: web session, API token issuance
# and the password-reset guard. The directory itself is stubbed at the
# Ldap::Authenticator boundary (protocol details are covered by its own spec).
RSpec.describe "Sessions via LDAP" do
  let(:user)       { create(:user, :ldap, ldap_uid: "sascha") }
  let!(:household) { create(:household, admin: user) }

  def stub_directory(result)
    authenticator = instance_double(Ldap::Authenticator)
    if result.is_a?(Class) && result <= StandardError
      allow(authenticator).to receive(:authenticate).and_raise(result, "connection refused")
    else
      allow(authenticator).to receive(:authenticate).and_return(result)
    end
    allow(Ldap::Authenticator).to receive(:new).and_return(authenticator)
    authenticator
  end

  def entry
    Ldap::Authenticator::Entry.new(uid: "sascha", dn: "uid=sascha,dc=example,dc=test", email: nil, name: nil)
  end

  context "with a configured connection" do
    let!(:connection) { create(:ldap_connection, household: household) }

    it "signs the user in when the directory accepts the password" do
      authenticator = stub_directory(entry)
      post login_path, params: { email: user.email, password: "ldap-pw" }

      expect(response).to redirect_to(root_path)
      expect(authenticator).to have_received(:authenticate).with("sascha", "ldap-pw")
      get root_path
      expect(response).to have_http_status(:ok) # session established
    end

    it "rejects the login when the directory rejects the password" do
      stub_directory(nil)
      post login_path, params: { email: user.email, password: "wrong" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "does not fall back to the dormant local password" do
      stub_directory(nil)
      post login_path, params: { email: user.email, password: "password123" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects the login when the directory is unreachable (no local fallback)" do
      stub_directory(Ldap::Error)
      post login_path, params: { email: user.email, password: "ldap-pw" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "still blocks pending (unactivated) accounts" do
      pending_user = create(:user, :pending, :ldap)
      create(:membership, user: pending_user, household: household)
      stub_directory(entry)
      post login_path, params: { email: pending_user.email, password: "ldap-pw" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "leaves non-linked users on the local password path" do
      local_user = create(:user)
      create(:membership, user: local_user, household: household)
      stub_directory(nil) # would fail if consulted
      post login_path, params: { email: local_user.email, password: "password123" }
      expect(response).to redirect_to(root_path)
    end

    describe "password reset" do
      it "sends no reset mail for an LDAP-linked account" do
        expect do
          post password_resets_path, params: { email: user.email }
        end.not_to(change { ActionMailer::Base.deliveries.size })
        # Same generic notice as always — no account enumeration.
        expect(response).to redirect_to(login_path)
      end

      it "still sends the mail for local accounts" do
        local_user = create(:user)
        create(:membership, user: local_user, household: household)
        expect do
          post password_resets_path, params: { email: local_user.email }
        end.to change { ActionMailer::Base.deliveries.size }.by(1)
      end

      it "refuses a reset token issued before the account was linked" do
        user.deliver_reset_password_instructions!
        token = user.reload.reset_password_token

        patch password_reset_path(token),
              params: { user: { password: "newpassword1", password_confirmation: "newpassword1" } }
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to eq(I18n.t("password_reset.ldap_managed"))
      end
    end

    describe "API sessions" do
      it "issues a token when the directory accepts the password" do
        stub_directory(entry)
        post "/api/v1/sessions", params: { email: user.email, password: "ldap-pw" }
        expect(response).to have_http_status(:created)
        expect(response.parsed_body["token"]).to be_present
      end

      it "rejects wrong directory credentials" do
        stub_directory(nil)
        post "/api/v1/sessions", params: { email: user.email, password: "password123" }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  context "without a connection (deleted or never configured)" do
    it "falls back to the local password even for linked users" do
      post login_path, params: { email: user.email, password: "password123" }
      expect(response).to redirect_to(root_path)
    end

    it "falls back on the API as well" do
      post "/api/v1/sessions", params: { email: user.email, password: "password123" }
      expect(response).to have_http_status(:created)
    end
  end
end
