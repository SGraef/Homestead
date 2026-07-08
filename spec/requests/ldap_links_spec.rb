# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "LdapLinks" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin) }
  let(:member)     { create(:user) }

  before do
    create(:membership, user: member, household: household)
    login_via_post(member)
  end

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

  def entry(uid)
    Ldap::Authenticator::Entry.new(uid: uid, dn: "uid=#{uid},dc=example,dc=test", email: nil, name: nil)
  end

  context "with a configured connection" do
    let!(:connection) { create(:ldap_connection, household: household) }

    it "shows the link form" do
      get ldap_link_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("ldap.link.link_button"))
    end

    it "links the current user after a successful directory bind" do
      authenticator = stub_directory(entry("Sascha"))
      post ldap_link_path, params: { ldap_username: "sascha", ldap_password: "ldap-pw" }

      expect(response).to redirect_to(ldap_link_path)
      # Stores the directory's canonical uid, not the typed one.
      expect(member.reload.ldap_uid).to eq("Sascha")
      expect(authenticator).to have_received(:authenticate).with("sascha", "ldap-pw")
    end

    it "rejects wrong directory credentials" do
      stub_directory(nil)
      post ldap_link_path, params: { ldap_username: "sascha", ldap_password: "wrong" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(member.reload.ldap_uid).to be_nil
    end

    it "reports an unreachable directory without linking" do
      stub_directory(Ldap::Error)
      post ldap_link_path, params: { ldap_username: "sascha", ldap_password: "pw" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("connection refused")
      expect(member.reload.ldap_uid).to be_nil
    end

    it "refuses a uid that is already linked to another user" do
      admin.update!(ldap_uid: "sascha")
      stub_directory(entry("sascha"))
      post ldap_link_path, params: { ldap_username: "sascha", ldap_password: "pw" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(member.reload.ldap_uid).to be_nil
    end

    it "unlinks the current user" do
      member.update!(ldap_uid: "sascha")
      delete ldap_link_path
      expect(response).to redirect_to(ldap_link_path)
      expect(member.reload.ldap_uid).to be_nil
    end
  end

  context "without a configured connection" do
    it "explains that LDAP is not set up" do
      get ldap_link_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("ldap.link.not_configured"))
    end

    it "does not link" do
      post ldap_link_path, params: { ldap_username: "sascha", ldap_password: "pw" }
      expect(response).to redirect_to(ldap_link_path)
      expect(member.reload.ldap_uid).to be_nil
    end
  end
end
