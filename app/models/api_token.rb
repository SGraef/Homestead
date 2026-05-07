# frozen_string_literal: true
# typed: true

# Stateless bearer token for the JSON API. Only the SHA-256 digest is stored;
# the plaintext value is returned exactly once at creation time.
class ApiToken < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true

  attr_reader :plaintext

  scope :active, -> { where(revoked_at: nil) }

  before_validation :generate_token, on: :create

  # Find an active token by the bearer plaintext.
  # @param plaintext [String]
  # @return [ApiToken, nil]
  def self.authenticate(plaintext)
    return nil if plaintext.to_s.empty?

    active.find_by(token_digest: digest_for(plaintext))
  end

  # @param plaintext [String]
  # @return [String] hex SHA-256 digest
  def self.digest_for(plaintext)
    Digest::SHA256.hexdigest(plaintext.to_s)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def touch_used!
    update_column(:last_used_at, Time.current)
  end

  private

  def generate_token
    return if token_digest.present?

    @plaintext = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest_for(@plaintext)
  end
end
