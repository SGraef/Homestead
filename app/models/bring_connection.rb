# frozen_string_literal: true
# typed: false

# Stores a household's Bring! account binding. The Bring! email + an access /
# refresh token are kept here so the background sync job can call the Bring!
# REST API on the household's behalf without re-prompting for the password
# every time.
#
# Tokens expire (~1h for access, longer for refresh). On a 401 the client
# tries the refresh endpoint; if that fails too, `access_token` is cleared
# and the household has to reconnect via the connect form.
#
# Tokens are encrypted at rest via Active Record encryption (keys derived from
# SECRET_KEY_BASE — see config/initializers/active_record_encryption.rb;
# rotating it makes stored tokens unreadable, so reconnect after rotation).
class BringConnection < ApplicationRecord
  belongs_to :household

  encrypts :access_token
  encrypts :refresh_token

  validates :bring_email,     presence: true
  validates :bring_user_uuid, presence: true
  validates :country_code,    presence: true, length: { is: 2 }

  # @return [Boolean] true once a list has been picked and we have a live token.
  def connected?
    access_token.present? && default_list_uuid.present?
  end

  # @return [Boolean]
  def access_token_expired?
    return true if access_token.blank?

    access_token_expires_at.present? && access_token_expires_at <= Time.current
  end
end
