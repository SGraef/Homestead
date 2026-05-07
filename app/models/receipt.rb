# frozen_string_literal: true
# typed: true

# A scanned grocery receipt. Lifecycle:
#
#   pending   — uploaded; OCR job not finished yet
#   parsed    — OCR + parser ran; user has not confirmed line items yet
#   confirmed — user accepted (or edited) the parsed lines; products /
#               stores / prices have been written from this receipt
#   failed    — OCR or parsing blew up; see {#error_message}
#
# A confirmed receipt is the primary way a household imports prices in bulk.
# The attached file is a photo (JPEG/PNG/HEIC) or a PDF; PDFs are rasterized
# at OCR time (see {ReceiptScanner::Adapters::Tesseract}).
class Receipt < ApplicationRecord
  STATUSES = %w[pending parsed failed confirmed].freeze
  ACCEPTED_MIME_TYPES = %w[
    image/jpeg image/png image/webp image/heic image/heif
    application/pdf
  ].freeze

  belongs_to :household
  belongs_to :store, optional: true
  belongs_to :user,  optional: true
  has_many :receipt_line_items, -> { order(:position, :id) }, dependent: :destroy
  has_one_attached :image

  validates :status, inclusion: { in: STATUSES }
  validate :image_must_be_attached
  validate :image_must_be_supported_type

  scope :recent, -> { order(created_at: :desc) }

  # @return [Boolean]
  def confirmable?
    status == "parsed"
  end

  # Confirmed receipts have already written {Product}/{Store}/{Price} rows;
  # re-OCR'ing would orphan them. Otherwise re-processing is always safe --
  # we destroy the old line items and let the job rebuild them.
  # @return [Boolean]
  def reprocessable?
    status != "confirmed" && image.attached?
  end

  # Wipe parsed state and re-enqueue OCR. Used both manually (the "Retry"
  # button) and to recover from a transient external failure.
  # @return [self]
  def reprocess!
    Receipt.transaction do
      receipt_line_items.destroy_all
      update!(
        status:              "pending",
        raw_text:            nil,
        detected_store_name: nil,
        purchased_on:        nil,
        subtotal_cents:      nil,
        parsed_at:           nil,
        error_message:       nil,
        store:               nil
      )
    end
    ProcessReceiptJob.perform_later(id)
    self
  end

  # @return [Boolean] true if the attached file is a PDF (and so should be
  #   rendered as a download / iframe rather than an <img>).
  def pdf?
    image.attached? && image.content_type == "application/pdf"
  end

  private

  def image_must_be_attached
    errors.add(:image, :blank) unless image.attached?
  end

  def image_must_be_supported_type
    return unless image.attached?
    return if ACCEPTED_MIME_TYPES.include?(image.content_type)

    errors.add(:image, :unsupported_type, accepted: ACCEPTED_MIME_TYPES.join(", "))
  end
end
