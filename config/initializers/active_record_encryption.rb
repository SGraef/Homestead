# frozen_string_literal: true
# typed: false

# Configure Active Record's at-rest encryption (used by models that
# declare `encrypts :some_column`) by deriving its three required keys
# from SECRET_KEY_BASE.
#
# Why derive instead of using credentials.yml.enc:
# * Homestead deployments don't ship a master.key today (the Unraid
#   template uses RAILS_MASTER_KEY only if the operator chose to bake
#   credentials.yml.enc into the image themselves).
# * SECRET_KEY_BASE is already a required env var, so reusing it as a
#   seed gives us deterministic keys without adding more
#   ops-surface-area.
#
# We call `ActiveRecord::Encryption.configure` directly because the
# Rails railtie pulls keys from credentials at the
# `active_record_encryption.configuration` initializer step, which
# runs before user initializers; setting
# `config.active_record.encryption.*` here would be too late.
#
# Tradeoff: rotating SECRET_KEY_BASE makes every encrypted column
# unreadable. Don't rotate without a re-encryption plan.

return if Rails.application.secret_key_base.blank?

require "digest"

Rails.application.config.after_initialize do
  seed = Rails.application.secret_key_base

  ActiveRecord::Encryption.configure(
    primary_key:         Digest::SHA256.digest("pantria/ar-encrypt/primary:#{seed}"),
    deterministic_key:   Digest::SHA256.digest("pantria/ar-encrypt/deterministic:#{seed}"),
    key_derivation_salt: Digest::SHA256.hexdigest("pantria/ar-encrypt/salt:#{seed}")
  )
end
