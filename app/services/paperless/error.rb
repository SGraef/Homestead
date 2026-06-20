# frozen_string_literal: true
# typed: false

module Paperless
  # Raised for any non-success response from paperless-ngx (or a transport
  # failure). {AuthError} is the 401/403 subclass.
  class Error < StandardError; end
end
