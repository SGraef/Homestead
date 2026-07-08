# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "LdapConnections" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin) }

  describe "as an admin" do
    before { login_via_post(admin) }

    it "creates the connection" do
      expect do
        post ldap_connection_path, params: { ldap_connection: {
          host: "ldap.home.lan", encryption: "start_tls", base_dn: "dc=home,dc=lan",
          bind_dn: "cn=readonly,dc=home,dc=lan", bind_password: "secret", uid_attribute: "uid"
        } }
      end.to change(LdapConnection, :count).by(1)
      expect(response).to redirect_to(ldap_connection_path)
      expect(household.reload.ldap_connection.host).to eq("ldap.home.lan")
    end

    it "rejects an unparsable user filter" do
      post ldap_connection_path, params: { ldap_connection: {
        host: "ldap.home.lan", base_dn: "dc=home,dc=lan", user_filter: "(((broken"
      } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(LdapConnection.count).to eq(0)
    end

    it "keeps the stored bind password when the field is left blank on update" do
      create(:ldap_connection, household: household, bind_password: "old-secret")
      patch ldap_connection_path, params: { ldap_connection: { host: "new.home.lan", bind_password: "" } }
      expect(response).to redirect_to(ldap_connection_path)
      connection = household.reload.ldap_connection
      expect(connection.host).to eq("new.home.lan")
      expect(connection.bind_password).to eq("old-secret")
    end

    it "removes the connection but keeps users' ldap_uid links" do
      create(:ldap_connection, household: household)
      admin.update!(ldap_uid: "sascha")
      delete ldap_connection_path
      expect(LdapConnection.count).to eq(0)
      expect(admin.reload.ldap_uid).to eq("sascha")
    end

    describe "POST /ldap_connection/test" do
      let!(:connection) { create(:ldap_connection, household: household) }

      it "reports success and clears the last error" do
        connection.update_columns(last_error: "old failure")
        authenticator = instance_double(Ldap::Authenticator, test!: true)
        allow(Ldap::Authenticator).to receive(:new).with(connection).and_return(authenticator)

        post test_ldap_connection_path
        expect(response).to redirect_to(ldap_connection_path)
        expect(flash[:notice]).to eq(I18n.t("ldap.test_ok"))
        expect(connection.reload.last_error).to be_nil
      end

      it "stores and reports the failure" do
        authenticator = instance_double(Ldap::Authenticator)
        allow(authenticator).to receive(:test!).and_raise(Ldap::Error, "Invalid Credentials (code 49)")
        allow(Ldap::Authenticator).to receive(:new).and_return(authenticator)

        post test_ldap_connection_path
        expect(response).to redirect_to(ldap_connection_path)
        expect(flash[:alert]).to include("Invalid Credentials")
        expect(connection.reload.last_error).to include("Invalid Credentials")
      end
    end
  end

  describe "as a non-admin member" do
    let(:member) { create(:user) }

    before do
      create(:membership, user: member, household: household)
      login_via_post(member)
    end

    it "cannot view or change the connection" do
      get ldap_connection_path
      expect(response).to redirect_to(root_path) # Pundit denial

      post ldap_connection_path, params: { ldap_connection: { host: "x", base_dn: "dc=x" } }
      expect(response).to redirect_to(root_path)
      expect(LdapConnection.count).to eq(0)
    end
  end
end
