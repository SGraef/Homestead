# frozen_string_literal: true
# typed: false

# A household's binding to an LDAP directory (OpenLDAP, LLDAP, Active
# Directory, ...). Once configured, a user can link their local account to a
# directory entry (see {User#ldap_uid} and LdapLinksController); linked users
# then authenticate at login via an LDAP bind instead of the local bcrypt
# password.
#
# The service-account bind password is encrypted at rest via Active Record
# encryption (keys derived from SECRET_KEY_BASE). Both bind_dn and
# bind_password are optional: leaving them blank uses an anonymous bind for
# the user search, which many home directories (e.g. LLDAP with anonymous
# read) allow.
class LdapConnection < ApplicationRecord
  # Wire encryption for the connection: plain LDAP, STARTTLS upgrade on the
  # standard port, or implicit TLS (LDAPS).
  ENCRYPTIONS = %w[none start_tls simple_tls].freeze
  DEFAULT_PORTS = { "none" => 389, "start_tls" => 389, "simple_tls" => 636 }.freeze

  belongs_to :household

  encrypts :bind_password

  validates :host, presence: true, length: { maximum: 255 }
  validates :encryption, inclusion: { in: ENCRYPTIONS }
  validates :port, allow_nil:    true,
                   numericality: { only_integer: true, in: 1..65_535 }
  validates :base_dn, presence: true, length: { maximum: 255 }
  # Attribute names per RFC 4512 (letters, digits, hyphen; must start with a
  # letter) — also blocks filter-injection via a crafted attribute name.
  validates :uid_attribute, presence: true,
                            format:   { with: /\A[a-zA-Z][a-zA-Z0-9-]*\z/ }
  validate :user_filter_must_parse

  # @return [Boolean] true once the connection knows where and what to search.
  def connected?
    host.present? && base_dn.present?
  end

  # @return [Integer] explicit port, or the conventional one for the
  #   configured encryption (389 plain/STARTTLS, 636 LDAPS).
  def effective_port
    port || DEFAULT_PORTS.fetch(encryption, 389)
  end

  private

  # Reject a filter net-ldap can't parse at save time, so a typo surfaces in
  # the settings form instead of as a failed login later.
  def user_filter_must_parse
    return if user_filter.blank?

    Net::LDAP::Filter.construct(user_filter)
  rescue StandardError
    errors.add(:user_filter, :invalid)
  end
end
