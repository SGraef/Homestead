# frozen_string_literal: true
# typed: true

class ReceiptSerializer
  # @param receipt [Receipt]
  # @param include_lines [Boolean]
  # @return [Hash]
  def self.call(receipt, include_lines: false)
    payload = {
      id:                  receipt.id,
      status:              receipt.status,
      detected_store_name: receipt.detected_store_name,
      store_id:            receipt.store_id,
      purchased_on:        receipt.purchased_on,
      currency:            receipt.currency,
      subtotal_cents:      receipt.subtotal_cents,
      parsed_at:           receipt.parsed_at,
      confirmed_at:        receipt.confirmed_at,
      error_message:       receipt.error_message,
      image_url:           image_url_for(receipt),
      created_at:          receipt.created_at
    }
    if include_lines
      payload[:line_items] = receipt.receipt_line_items.map do |li|
        {
          id:                      li.id,
          position:                li.position,
          line_text:               li.line_text,
          parsed_name:             li.parsed_name,
          parsed_quantity:         li.parsed_quantity,
          parsed_unit_price_cents: li.parsed_unit_price_cents,
          parsed_total_cents:      li.parsed_total_cents,
          status:                  li.status,
          product_id:              li.product_id
        }
      end
    end
    payload
  end

  def self.image_url_for(receipt)
    return nil unless receipt.image.attached?

    Rails.application.routes.url_helpers.rails_blob_path(receipt.image, only_path: true)
  rescue StandardError
    nil
  end
end
