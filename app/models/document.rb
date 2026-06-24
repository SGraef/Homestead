# frozen_string_literal: true
# typed: false

# A stored household document -- a receipt, bill, invoice, contract, etc. The
# attached file (PDF or image) lives in Active Storage and Homestead is the
# source of truth for it.
#
# Lifecycle (the `status` column):
#
#   stored  — local archive only; either no paperless connection is configured
#             or the push hasn't started
#   pending — queued for / mid-flight upload to paperless-ngx
#   synced  — paperless consumed it; {#paperless_document_id} is set and the
#             classifier output (type / correspondent / tags) is mirrored here
#   failed  — upload or consumption failed; see {#error_message}
#
# Paperless is entirely optional: a household that never configures a
# {PaperlessConnection} just gets a local document archive and never leaves
# the `stored` state.
class Document < ApplicationRecord
  STATUSES = %w[stored pending synced failed].freeze
  # bill    — an invoice that may carry a payment due date
  # receipt — proof of a completed purchase; no due date, no reminder
  # other   — contracts, letters, ...; treated like a bill for reminders
  KINDS = %w[bill receipt other].freeze
  # Receipts, invoices and contracts arrive as scans or exports, so accept the
  # same broad set the receipt uploader does.
  ACCEPTED_MIME_TYPES = %w[
    image/jpeg image/png image/webp image/heic image/heif
    application/pdf
  ].freeze

  belongs_to :household
  belongs_to :user, optional: true
  has_one_attached :file
  # Payment-reminder todos generated from this bill. Nullified (not destroyed)
  # when the document is deleted so an in-flight reminder survives.
  has_many :reminder_todos, class_name: "Todo", foreign_key: :source_document_id,
                            dependent: :nullify, inverse_of: :source_document

  validates :title, presence: true, length: { maximum: 255 }
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS }
  validate :file_must_be_attached, on: :create
  validate :file_must_be_supported_type, on: :create

  scope :recent, -> { order(created_at: :desc) }

  # @return [Boolean] receipts are completed purchases -- no payment reminder.
  def receipt?
    kind == "receipt"
  end

  # @return [Boolean] true once paperless has consumed this document.
  def paperless_linked?
    paperless_document_id.present?
  end

  # The paperless-ngx tags mirrored back from the classifier.
  # @return [Array<String>]
  def paperless_tags_list
    paperless_tags.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  private

  def file_must_be_attached
    errors.add(:file, :blank) unless file.attached?
  end

  def file_must_be_supported_type
    return unless file.attached?
    return if ACCEPTED_MIME_TYPES.include?(file.blob.content_type)

    errors.add(:file, :invalid)
  end
end
