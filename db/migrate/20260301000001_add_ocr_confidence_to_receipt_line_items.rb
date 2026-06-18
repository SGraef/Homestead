# frozen_string_literal: true

class AddOcrConfidenceToReceiptLineItems < ActiveRecord::Migration[8.0]
  def change
    # Per-line OCR confidence (0-100, mean of the line's word confidences from
    # Tesseract's TSV output). Nullable: legacy rows and any line we couldn't
    # match back to the OCR data stay nil ("unknown").
    add_column :receipt_line_items, :ocr_confidence, :integer
  end
end
