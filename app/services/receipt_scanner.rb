# frozen_string_literal: true
# typed: true

# Pipeline that turns a receipt image into a structured {Result}.
#
#   raw image  →  Adapter (OCR)  →  raw text  →  Parser  →  Result
#
# The adapter is pluggable — production uses {Adapters::Tesseract} (system
# binary), tests substitute a fake via `ReceiptScanner.adapter = ...`.
module ReceiptScanner
  class Error < StandardError; end
  class OcrError < Error; end

  # Top-level outcome: raw OCR output plus the parsed structure.
  Outcome = Struct.new(:raw_text, :result, keyword_init: true)

  # Structured parser output.
  Result = Struct.new(
    :store_name,     # String, best-effort guess at the merchant
    :purchased_on,   # Date, nil if no date detected
    :currency,       # ISO 4217 code, defaults to EUR
    :subtotal_cents, # Integer
    :line_items,     # Array<LineItem>
    keyword_init: true
  )

  LineItem = Struct.new(
    :position,
    :line_text,
    :name,
    :quantity,
    :unit_price_cents,
    :total_cents,
    keyword_init: true
  )

  class << self
    # @return [#extract_text]
    def adapter
      @adapter ||= Adapters::Tesseract.new
    end

    # @param adapter [#extract_text]
    attr_writer :adapter

    # @param image_path [String, Pathname] path to a readable image file
    # @return [Outcome]
    def call(image_path)
      raw = adapter.extract_text(image_path.to_s)
      Outcome.new(raw_text: raw, result: Parser.parse(raw))
    end
  end
end
