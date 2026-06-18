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
    :confidence,     # Integer 0-100, mean OCR confidence of the line (nil if unknown)
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
      Telemetry.in_span("receipt_scanner.call",
                        attributes: { "receipt_scanner.image_path" => image_path.to_s }) do |span|
        started = Time.current
        raw     = adapter.extract_text(image_path.to_s)
        confs   = adapter.respond_to?(:line_confidences) ? adapter.line_confidences : {}
        result  = Parser.parse(raw, line_confidences: confs)

        if span.respond_to?(:set_attribute)
          span.set_attribute("receipt_scanner.raw_text_length", raw.to_s.length)
          span.set_attribute("receipt_scanner.line_items_count", result.line_items.size)
          span.set_attribute("receipt_scanner.detected_total_cents", result.subtotal_cents || 0)
        end

        duration_ms = ((Time.current - started) * 1000).to_i
        record_metrics(raw, result, duration_ms)

        Outcome.new(raw_text: raw, result: result)
      end
    end

    private

    def record_metrics(raw, result, duration_ms)
      Telemetry.histogram("pantria.receipt_scanner.duration_ms",
                          unit:        "ms",
                          description: "End-to-end time from image -> parsed Result")
               .record(duration_ms)

      Telemetry.counter("pantria.receipt_scanner.line_items_detected",
                        description: "Number of product lines the parser pulled from the OCR text")
               .add(result.line_items.size)

      # Detect "empty OCR" failures so they show up on a dashboard
      # rather than being silently swallowed.
      return unless raw.to_s.strip.empty?

      Telemetry.counter("pantria.receipt_scanner.empty_ocr_total",
                        description: "Receipts whose OCR returned no text at all").add(1)
    end
  end
end
