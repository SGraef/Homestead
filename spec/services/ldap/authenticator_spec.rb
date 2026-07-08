# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Ldap::Authenticator do
  subject(:authenticator) { described_class.new(connection) }

  let(:connection) do
    build(:ldap_connection, user_filter: "(objectClass=person)", verify_tls: false)
  end
  let(:client) { instance_double(Net::LDAP) }

  before { allow(Net::LDAP).to receive(:new).and_return(client) }

  # net-ldap's get_operation_result returns an OpenStruct-ish object; a plain
  # Struct keeps the stub verifiable without depending on gem internals.
  def operation_result(message, code)
    Struct.new(:message, :code).new(message, code)
  end

  def directory_entry(uid: "sascha")
    entry = Net::LDAP::Entry.new("uid=#{uid},ou=people,dc=example,dc=test")
    entry["uid"]  = [uid]
    entry["mail"] = ["#{uid}@example.test"]
    entry["cn"]   = ["Sascha S"]
    entry
  end

  describe "#authenticate" do
    it "returns the entry when the directory accepts the credentials" do
      allow(client).to receive(:bind_as).and_return([directory_entry])

      result = authenticator.authenticate("sascha", "pw")
      expect(result.uid).to eq("sascha")
      expect(result.dn).to eq("uid=sascha,ou=people,dc=example,dc=test")
      expect(result.email).to eq("sascha@example.test")
      expect(result.name).to eq("Sascha S")
    end

    it "prefers the directory's canonical uid casing over the typed one" do
      allow(client).to receive(:bind_as).and_return([directory_entry(uid: "Sascha")])
      expect(authenticator.authenticate("sAsChA", "pw").uid).to eq("Sascha")
    end

    it "returns nil when the directory rejects the credentials" do
      allow(client).to receive(:bind_as).and_return(false)
      expect(authenticator.authenticate("sascha", "wrong")).to be_nil
    end

    it "rejects a blank password without contacting the server (anonymous-bind guard)" do
      expect(authenticator.authenticate("sascha", "")).to be_nil
      expect(Net::LDAP).not_to have_received(:new)
    end

    it "rejects a blank username without contacting the server" do
      expect(authenticator.authenticate("", "pw")).to be_nil
      expect(Net::LDAP).not_to have_received(:new)
    end

    it "wraps transport failures in Ldap::Error" do
      allow(client).to receive(:bind_as).and_raise(Net::LDAP::Error, "connection refused")
      expect { authenticator.authenticate("sascha", "pw") }
        .to raise_error(Ldap::Error, /connection refused/)
    end

    it "configures the client from the connection settings" do
      allow(client).to receive(:bind_as).and_return(false)
      authenticator.authenticate("sascha", "pw")

      expect(Net::LDAP).to have_received(:new).with(
        hash_including(
          host:       "ldap.example.test",
          port:       389,
          auth:       hash_including(username: "cn=readonly,dc=example,dc=test"),
          encryption: { method: :start_tls, tls_options: { verify_mode: OpenSSL::SSL::VERIFY_NONE } }
        )
      )
    end

    it "omits encryption for plain LDAP and auth for anonymous binds" do
      connection.assign_attributes(encryption: "none", bind_dn: nil, bind_password: nil)
      allow(client).to receive(:bind_as).and_return(false)
      authenticator.authenticate("sascha", "pw")

      options = nil
      expect(Net::LDAP).to have_received(:new) { |opts| options = opts }
      expect(options).not_to have_key(:encryption)
      expect(options).not_to have_key(:auth)
    end
  end

  describe "#test!" do
    it "returns true when the service bind and base-DN lookup succeed" do
      allow(client).to receive_messages(bind: true, search: [Net::LDAP::Entry.new(connection.base_dn)])
      expect(authenticator.test!).to be(true)
    end

    it "raises with the server's message when the bind fails" do
      allow(client).to receive_messages(bind:                 false,
                                        get_operation_result: operation_result("Invalid Credentials", 49))

      expect { authenticator.test! }.to raise_error(Ldap::Error, /Invalid Credentials \(code 49\)/)
    end

    it "raises when the base DN cannot be read" do
      allow(client).to receive_messages(bind: true, search: nil,
                                        get_operation_result: operation_result("No Such Object", 32))

      expect { authenticator.test! }.to raise_error(Ldap::Error, /No Such Object/)
    end

    it "wraps connection failures in Ldap::Error" do
      allow(client).to receive(:bind).and_raise(Errno::ECONNREFUSED)
      expect { authenticator.test! }.to raise_error(Ldap::Error, /ECONNREFUSED/)
    end
  end
end
