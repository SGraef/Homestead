# frozen_string_literal: true
# typed: false

# Runs OCR + parsing for a single {Receipt} asynchronously, persisting the
# raw OCR output and creating one {ReceiptLineItem} per detected line.
#
# Retry policy:
#   - Up to {MAX_ATTEMPTS} attempts with polynomial backoff.
#   - Between attempts the receipt is left as "pending" with the latest error
#     surfaced via {Receipt#error_message}, so the user sees that the system
#     is still working on it.
#   - On the *final* failed attempt the receipt is flipped to "failed" and the
#     user-facing "Retry OCR" button (or the manual {Receipt#reprocess!}) is
#     the way out.
class ProcessReceiptJob < ApplicationJob
  MAX_ATTEMPTS = 3

  # Receipt OCR is CPU-bound (tesseract per page) and slow enough that
  # one job can hog a worker thread for tens of seconds. Pinning it
  # to a dedicated queue means the worker pool sized for `receipts`
  # in config/queue.yml (1 thread by default) caps concurrent OCR
  # runs, while the `default` queue keeps draining fast recurring
  # stuff (Bring sync, IMAP poll, offer sync) without head-of-line
  # blocking from a long-running scan.
  queue_as :receipts

  retry_on StandardError, attempts: MAX_ATTEMPTS, wait: :polynomially_longer
  # Row was deleted between enqueue and execution -- nothing to retry.
  discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

  # @param receipt_id [Integer]
  def perform(receipt_id)
    receipt = Receipt.find(receipt_id)
    return unless receipt.image.attached?

    receipt.image.open do |file|
      outcome = ReceiptScanner.call(file.path)
      persist!(receipt, outcome)
    end
  rescue StandardError => e
    final_attempt = executions >= MAX_ATTEMPTS
    Receipt.where(id: receipt_id).update_all(
      status:        final_attempt ? "failed" : "pending",
      error_message: e.message.to_s.first(1000),
      updated_at:    Time.current
    )
    raise
  end

  private

  def persist!(receipt, outcome)
    Receipt.transaction do
      receipt.update!(
        raw_text:            outcome.raw_text,
        detected_store_name: outcome.result.store_name,
        purchased_on:        outcome.result.purchased_on,
        currency:            outcome.result.currency || "EUR",
        subtotal_cents:      outcome.result.subtotal_cents,
        status:              "parsed",
        parsed_at:           Time.current,
        error_message:       nil
      )

      # `reprocess!` already wiped the previous line items, but be defensive in
      # case the job ran after some other code path left rows behind.
      receipt.receipt_line_items.destroy_all if receipt.receipt_line_items.exists?

      outcome.result.line_items.each do |li|
        receipt.receipt_line_items.create!(
          position:                li.position,
          line_text:               li.line_text,
          parsed_name:             li.name,
          parsed_quantity:         li.quantity,
          parsed_unit_price_cents: li.unit_price_cents,
          parsed_total_cents:      li.total_cents,
          ocr_confidence:          li.confidence,
          status:                  "unmatched"
        )
      end
    end
  end
end
