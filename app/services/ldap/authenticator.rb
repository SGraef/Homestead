# frozen_string_literal: true
# typed: false

module Ldap
  # Thin wrapper around net-ldap for the two operations the app needs:
  # verifying a user's directory credentials (search + rebind via bind_as)
  # and checking the configured service bind for the settings "test" button.
  class Authenticator
    CONNECT_TIMEOUT_S = 5

    # A successfully authenticated directory entry, reduced to what the app
    # stores/displays. uid carries the directory's canonical casing.
    Entry = Struct.new(:uid, :dn, :email, :name, keyword_init: true)

    # @param connection [LdapConnection]
    def initialize(connection)
      @connection = connection
    end

    # Verify username + password against the directory.
    #
    # An empty password is rejected before it reaches the server: LDAP treats
    # a bind with a DN and no password as an *anonymous* bind that succeeds,
    # which would let anyone log in as any linked user.
    #
    # @param username [String] value of the configured uid attribute
    # @param password [String]
    # @return [Entry, nil] nil when the credentials don't check out
    # @raise [Ldap::Error] when the directory can't be reached/searched
    def authenticate(username, password)
      return nil if username.blank? || password.blank?

      client  = build_client
      entries = client.bind_as(base: @connection.base_dn, filter: user_filter(username), password: password)
      raw = entries.is_a?(Array) ? entries.first : nil
      return nil unless raw

      to_entry(raw, username)
    rescue Net::LDAP::Error, OpenSSL::SSL::SSLError, IOError, SystemCallError => e
      raise Error, "#{e.class}: #{e.message}"
    end

    # Service-credential bind plus a base-scope read of the base DN, so the
    # settings form catches both bad credentials and a mistyped base DN.
    #
    # @return [true]
    # @raise [Ldap::Error]
    def test!
      client = build_client
      raise Error, operation_message(client) unless client.bind

      found = client.search(base: @connection.base_dn, scope: Net::LDAP::SearchScope_BaseObject,
                            attributes: %w[dn], return_result: true)
      raise Error, operation_message(client) unless found

      true
    rescue Net::LDAP::Error, OpenSSL::SSL::SSLError, IOError, SystemCallError => e
      raise Error, "#{e.class}: #{e.message}"
    end

    private

    # (&(uid=<escaped username>)<admin-configured extra filter>)
    def user_filter(username)
      filter = Net::LDAP::Filter.eq(@connection.uid_attribute, Net::LDAP::Filter.escape(username))
      return filter if @connection.user_filter.blank?

      Net::LDAP::Filter.join(filter, Net::LDAP::Filter.construct(@connection.user_filter))
    end

    def build_client
      options = {
        host:            @connection.host,
        port:            @connection.effective_port,
        connect_timeout: CONNECT_TIMEOUT_S
      }
      if @connection.bind_dn.present?
        options[:auth] = { method:   :simple,
                           username: @connection.bind_dn,
                           password: @connection.bind_password.to_s }
      end
      unless @connection.encryption == "none"
        options[:encryption] = { method: @connection.encryption.to_sym, tls_options: tls_options }
      end
      Net::LDAP.new(options)
    end

    # Explicit either way — never rely on net-ldap's TLS defaults.
    def tls_options
      if @connection.verify_tls?
        OpenSSL::SSL::SSLContext::DEFAULT_PARAMS
      else
        { verify_mode: OpenSSL::SSL::VERIFY_NONE }
      end
    end

    def to_entry(raw, fallback_uid)
      Entry.new(
        uid:   first_value(raw, @connection.uid_attribute) || fallback_uid,
        dn:    raw.dn.to_s,
        email: first_value(raw, "mail"),
        name:  first_value(raw, "displayName") || first_value(raw, "cn")
      )
    end

    # Net::LDAP::Entry attributes are arrays; missing ones are empty.
    def first_value(raw, attribute)
      Array(raw[attribute]).first&.to_s.presence
    end

    def operation_message(client)
      result = client.get_operation_result
      "#{result.message} (code #{result.code})"
    end
  end
end
