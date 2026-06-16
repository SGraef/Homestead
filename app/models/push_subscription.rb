# frozen_string_literal: true
# typed: false

# A browser Web Push subscription for one user/device. Only the SHA-256 digest
# of the endpoint is uniquely indexed (the raw endpoint is too long).
class PushSubscription < ApplicationRecord
  belongs_to :user
  belongs_to :household

  validates :endpoint, presence: true
  validates :endpoint_digest, presence: true, uniqueness: true
  validates :p256dh, presence: true
  validates :auth, presence: true

  before_validation :set_digest

  def self.digest_for(endpoint)
    Digest::SHA256.hexdigest(endpoint.to_s)
  end

  private

  def set_digest
    self.endpoint_digest = self.class.digest_for(endpoint) if endpoint.present?
  end
end
