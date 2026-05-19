# frozen_string_literal: true
# typed: true

module Bring
  # Distinct from {Error} so job-level `retry_on Bring::Error` doesn't
  # retry login-state problems indefinitely. The controller flow
  # surfaces auth failures back to the user (reconnect dialog).
  class AuthError < Error; end
end
