# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe LdapConnection do
  subject(:connection) { build(:ldap_connection) }

  it "is valid with the factory defaults" do
    expect(connection).to be_valid
  end

  it { is_expected.to validate_presence_of(:host) }
  it { is_expected.to validate_presence_of(:base_dn) }
  it { is_expected.to validate_inclusion_of(:encryption).in_array(LdapConnection::ENCRYPTIONS) }

  it "rejects an out-of-range port" do
    connection.port = 70_000
    expect(connection).not_to be_valid
  end

  it "rejects a uid attribute that is not a plain LDAP attribute name" do
    connection.uid_attribute = "uid)(cn=*"
    expect(connection).not_to be_valid
    expect(connection.errors[:uid_attribute]).to be_present
  end

  it "rejects a user filter net-ldap cannot parse" do
    connection.user_filter = "(((objectClass="
    expect(connection).not_to be_valid
    expect(connection.errors[:user_filter]).to be_present
  end

  it "accepts a well-formed user filter" do
    connection.user_filter = "(&(objectClass=person)(memberOf=cn=pantria,ou=groups,dc=example,dc=test))"
    expect(connection).to be_valid
  end

  describe "#effective_port" do
    it "uses the conventional port for the encryption when none is set" do
      expect(build(:ldap_connection, encryption: "start_tls", port: nil).effective_port).to eq(389)
      expect(build(:ldap_connection, encryption: "simple_tls", port: nil).effective_port).to eq(636)
    end

    it "prefers an explicit port" do
      expect(build(:ldap_connection, encryption: "simple_tls", port: 1636).effective_port).to eq(1636)
    end
  end

  describe "#connected?" do
    it "is true once host and base DN are present" do
      expect(connection).to be_connected
    end
  end

  it "encrypts the bind password at rest" do
    connection.save!
    raw = described_class.connection.select_value(
      "SELECT bind_password FROM ldap_connections WHERE id = #{connection.id}"
    )
    expect(raw).not_to include("service-secret")
    expect(connection.reload.bind_password).to eq("service-secret")
  end
end
