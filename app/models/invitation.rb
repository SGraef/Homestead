# frozen_string_literal: true
# typed: false

# An admin-issued invitation to join the single household. Self-registration is
# closed after first run, so invitations are how new members get an account.
#
# Security: only the SHA-256 digest of the token is stored (mirrors {ApiToken});
# the plaintext is emailed once and exposed via {#plaintext} only at creation /
# regeneration time. Tokens are single-use (consumed on accept) and expire.
class Invitation < ApplicationRecord
  EXPIRES_IN = 7.days

  belongs_to :household
  belongs_to :invited_by, class_name: "User", optional: true

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: Membership::ROLES }
  validates :token_digest, presence: true, uniqueness: true

  attr_reader :plaintext

  before_validation :normalize_email
  before_validation :generate_token, on: :create
  before_validation :set_expiry,     on: :create

  # Outstanding (neither accepted nor expired) invitations.
  scope :pending, -> { where(accepted_at: nil).where(arel_table[:expires_at].gt(Time.current)) }

  # Create (or refresh) a pending invitation for an email in this household and
  # return it with {#plaintext} populated so the caller can email the link.
  #
  # @return [Invitation]
  def self.invite!(household:, email:, role:, invited_by: nil)
    normalized = email.to_s.downcase.strip
    invitation = household.invitations.pending.find_or_initialize_by(email: normalized)
    invitation.role        = role.presence || "member"
    invitation.invited_by  = invited_by

    if invitation.persisted?
      invitation.regenerate_token!
    else
      invitation.save!
    end
    invitation
  end

  # Find a pending invitation by the emailed plaintext token.
  # @param plaintext [String]
  # @return [Invitation, nil]
  def self.authenticate(plaintext)
    return nil if plaintext.to_s.empty?

    pending.find_by(token_digest: digest_for(plaintext))
  end

  # @param plaintext [String]
  # @return [String] hex SHA-256 digest
  def self.digest_for(plaintext)
    Digest::SHA256.hexdigest(plaintext.to_s)
  end

  # Issue a fresh token + expiry on an existing invitation (used for resends),
  # returning the new plaintext.
  # @return [String]
  def regenerate_token!
    @plaintext = SecureRandom.urlsafe_base64(32)
    update!(token_digest: self.class.digest_for(@plaintext),
            expires_at:   EXPIRES_IN.from_now,
            accepted_at:  nil)
    @plaintext
  end

  # @return [Boolean]
  def expired? = expires_at.present? && expires_at <= Time.current

  # @return [Boolean]
  def accepted? = accepted_at.present?

  # Consume the invitation: create the user (active, no activation email -- the
  # invite link already proves email ownership), add the household membership,
  # and mark the invitation accepted. All-or-nothing.
  #
  # @return [User] the created, active user
  # @raise [ActiveRecord::RecordInvalid] if the user params are invalid
  def accept!(name:, password:, password_confirmation:)
    raise ActiveRecord::RecordNotFound if accepted? || expired?

    user = nil
    transaction do
      user = User.new(email: email, name: name,
                      password: password, password_confirmation: password_confirmation)
      user.skip_activation_needed_email  = true
      user.skip_activation_success_email = true
      user.save!
      user.activate!
      household.memberships.find_or_create_by!(user: user) { |m| m.role = role }
      update!(accepted_at: Time.current)
    end
    user
  end

  private

  def normalize_email
    self.email = email&.downcase&.strip
  end

  def generate_token
    return if token_digest.present?

    @plaintext = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest_for(@plaintext)
  end

  def set_expiry
    self.expires_at ||= EXPIRES_IN.from_now
  end
end
