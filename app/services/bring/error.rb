# frozen_string_literal: true
# typed: true

module Bring
  # Base error class for the Bring! HTTP client. Used by `retry_on
  # Bring::Error` in the job layer to retry transient failures
  # (network blips, 5xx) without swallowing real auth problems
  # (see {AuthError}).
  #
  # Lives in its own file so Zeitwerk's eager_load (CI) can autoload
  # the constant by path. Previously the class was defined as a
  # side-effect inside client.rb, which worked in dev (lazy load) but
  # broke under eager_load.
  class Error < StandardError; end
end
