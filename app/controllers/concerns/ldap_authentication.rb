# frozen_string_literal: true
# typed: false

# Shared LDAP credential check for the web and API login endpoints. A user
# linked to the directory ({User#ldap_user?}) authenticates via an LDAP bind
# while a connection is configured; the local bcrypt password lies dormant.
# Deleting the LDAP connection reverts everyone to local passwords — but a
# merely *unreachable* directory does not (silently falling back to possibly
# stale local passwords would defeat central account control).
module LdapAuthentication
  private

  # @return [Boolean] true when the household has a usable LDAP connection.
  def ldap_ready?
    Household.current&.ldap_connection&.connected? || false
  end

  # @param user [User] a user with ldap_uid set
  # @param password [String]
  # @return [Boolean] true when the directory confirms the password
  def ldap_password_valid?(user, password)
    connection = Household.current&.ldap_connection
    return false unless connection&.connected?

    Ldap::Authenticator.new(connection).authenticate(user.ldap_uid, password.to_s).present?
  rescue Ldap::Error => e
    Rails.logger.warn("[LDAP] authentication unavailable: #{e.message}")
    false
  end
end
