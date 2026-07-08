# frozen_string_literal: true
# typed: false

module Ldap
  # Raised for anything that prevents talking to the directory (connection
  # refused, TLS failure, bad service credentials, unparsable filter). A plain
  # failed user login is NOT an error — {Authenticator#authenticate} returns
  # nil for that, so callers can tell "wrong password" from "LDAP down".
  class Error < StandardError; end
end
