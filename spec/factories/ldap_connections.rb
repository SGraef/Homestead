# frozen_string_literal: true

FactoryBot.define do
  factory :ldap_connection do
    household
    host          { "ldap.example.test" }
    encryption    { "start_tls" }
    base_dn       { "dc=example,dc=test" }
    bind_dn       { "cn=readonly,dc=example,dc=test" }
    bind_password { "service-secret" }
    uid_attribute { "uid" }
    verify_tls    { true }
  end
end
