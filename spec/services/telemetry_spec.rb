# frozen_string_literal: true
# typed: false

require "rails_helper"

# Covers the OTel-off (no-op shim) mode -- the path CI / local-dev
# hit on every run, which the rest of the app implicitly depends on
# being silently free of side effects. With OTel on the SDK gems are
# loaded and the real exporters take over; that path is exercised by
# the OTel-ON smoke check in CI (see docs/OBSERVABILITY.md).
RSpec.describe Telemetry do
  describe ".enabled?" do
    it "is false when OTEL_EXPORTER_OTLP_ENDPOINT is unset" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OTEL_EXPORTER_OTLP_ENDPOINT").and_return(nil)
      expect(described_class).not_to be_enabled
    end
  end

  describe ".in_span (OTel off)" do
    it "yields a no-op span and returns the block value" do
      result = described_class.in_span("test.span", attributes: { foo: 1 }) do |span|
        span.set_attribute("bar", true)        # no-op, must not raise
        span.add_event("inner")                # no-op
        span.record_exception(StandardError.new) # no-op
        42
      end
      expect(result).to eq(42)
    end
  end

  describe ".counter / .histogram (OTel off)" do
    it "caches instruments by name and accepts add / record without raising" do
      described_class.instance_variable_set(:@instruments, {})

      c = described_class.counter("test.counter", description: "doc")
      expect(described_class.counter("test.counter")).to be(c) # cache hit

      h = described_class.histogram("test.hist", unit: "ms")
      expect { c.add(1, attributes: { foo: "bar" }) }.not_to raise_error
      expect { h.record(42) }.not_to raise_error
    end
  end

  describe ".log_event (OTel off)" do
    it "no-ops silently when OTel is disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)
      expect { described_class.log_event("nothing happens", severity: :warn) }
        .not_to raise_error
    end
  end

  describe "severity number mapping" do
    it "maps Rails severity symbols to OTel severity numbers" do
      expect(described_class.severity_number_for(:debug)).to eq(5)
      expect(described_class.severity_number_for(:info)).to  eq(9)
      expect(described_class.severity_number_for(:warn)).to  eq(13)
      expect(described_class.severity_number_for(:error)).to eq(17)
      expect(described_class.severity_number_for(:fatal)).to eq(21)
      expect(described_class.severity_number_for(:unknown)).to eq(9) # falls back to INFO
    end
  end
end
