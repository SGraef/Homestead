# frozen_string_literal: true
# typed: false

# The household's single external-calendar connection. Credentials and tokens
# are encrypted at rest (Active Record encryption, derived from SECRET_KEY_BASE
# — rotating it makes stored secrets unreadable; reconnect after rotation).
class CalendarConnection < ApplicationRecord
  PROVIDERS = %w[google].freeze
  STATUSES  = %w[disconnected connected error].freeze

  belongs_to :household
  has_many :calendar_events, dependent: :nullify

  encrypts :client_secret
  encrypts :access_token
  encrypts :refresh_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }

  def connected?
    status == "connected"
  end

  # OAuth completed (tokens present) — true even if the last API call errored,
  # so the settings UI keeps showing the picker/sync instead of reverting to the
  # Connect button on a transient/config failure.
  def linked?
    access_token.present? && refresh_token.present?
  end

  def configured?
    client_id.present? && client_secret.present?
  end

  def token_expired?
    token_expires_at.present? && token_expires_at <= Time.current
  end
end
