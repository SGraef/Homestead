# frozen_string_literal: true
# typed: false

module Paperless
  # The token was missing/rejected (HTTP 401/403). The connection stays saved
  # so the user can fix the token and retry rather than re-entering the URL.
  class AuthError < Error; end
end
