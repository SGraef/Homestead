# frozen_string_literal: true
# typed: false

# A household's binding to a self-hosted paperless-ngx instance: the base URL
# plus a per-user API token used to push documents and read back the
# classifier's output (document type / correspondent / tags).
#
# The token is encrypted at rest via Active Record encryption (keys derived
# from SECRET_KEY_BASE -- see config/initializers/active_record_encryption.rb;
# rotating it makes the stored token unreadable, so reconnect after rotation).
#
# The whole paperless feature is optional: with no connection (or an
# unconnected one) {Document}s behave as a plain local archive and nothing
# paperless-related is surfaced. See {Document}.
class PaperlessConnection < ApplicationRecord
  belongs_to :household

  encrypts :api_token

  validates :base_url, presence: true
  # A connection with no token can't reach paperless. On edit the controller
  # strips a blank token from the params (so "leave blank to keep" works), so
  # this only bites a brand-new connection saved without one.
  validates :api_token, presence: true
  validate  :base_url_must_be_http

  # @return [Boolean] true once we have somewhere to talk to and a credential.
  def connected?
    base_url.present? && api_token.present?
  end

  # Base URL without a trailing slash, so path joins don't double up.
  # @return [String]
  def normalized_base_url
    base_url.to_s.strip.chomp("/")
  end

  # Deep link into the paperless web UI for a given document id. We store only
  # the id (not a full URL) so moving paperless to a new host keeps every
  # existing link working.
  # @param document_id [Integer, nil]
  # @return [String, nil]
  def document_url(document_id)
    return nil if document_id.blank? || normalized_base_url.empty?

    "#{normalized_base_url}/documents/#{document_id}/"
  end

  # @return [Array<String>] configured default tags, normalised + de-duped.
  def default_tags_list
    default_tags.to_s.split(",").map(&:strip).reject(&:empty?).uniq
  end

  private

  def base_url_must_be_http
    return if base_url.blank?

    uri = URI.parse(base_url.to_s.strip)
    return if uri.is_a?(URI::HTTP) && uri.host.present?

    errors.add(:base_url, :invalid)
  rescue URI::InvalidURIError
    errors.add(:base_url, :invalid)
  end
end
