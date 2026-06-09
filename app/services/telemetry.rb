# frozen_string_literal: true
# typed: false

# Thin wrapper around the OpenTelemetry tracer / meter / logger
# provider so the rest of the app can call Telemetry.in_span(...) /
# Telemetry.counter(...).add(1) without caring whether OTel is
# actually wired up.
#
# Two modes:
#   * OTel ENABLED (env var set, SDK loaded by the initializer):
#     calls land on real exporters, get correlated with the current
#     trace context, etc.
#   * OTel OFF (env var unset, SDK never required): we use no-op
#     shims so call sites stay unchanged and zero allocations leak
#     from the SDK into the hot path.
module Telemetry
  INSTRUMENTATION_NAME    = "pantria"
  INSTRUMENTATION_VERSION = "1.0.0"

  module_function

  # @return [Boolean] true when the SDK was wired up by the initializer.
  def enabled?
    defined?(OpenTelemetry::SDK) && ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present?
  end

  # @return [OpenTelemetry::Trace::Tracer, NoopTracer]
  def tracer
    @tracer ||= if defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:tracer_provider)
                  OpenTelemetry.tracer_provider.tracer(INSTRUMENTATION_NAME,
                                                       INSTRUMENTATION_VERSION)
                else
                  NoopTracer.new
                end
  end

  # @return [OpenTelemetry::Metrics::Meter, NoopMeter]
  def meter
    @meter ||= if defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:meter_provider)
                 OpenTelemetry.meter_provider.meter(INSTRUMENTATION_NAME,
                                                    version: INSTRUMENTATION_VERSION)
               else
                 NoopMeter.new
               end
  end

  # @return [OpenTelemetry::Logs::Logger, NoopLogger]
  def logger
    @logger ||= if defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:logger_provider)
                  OpenTelemetry.logger_provider.logger(name:    INSTRUMENTATION_NAME,
                                                       version: INSTRUMENTATION_VERSION)
                else
                  NoopLogger.new
                end
  end

  # Cached counter / histogram instruments by name -- creating a
  # duplicate (same name + kind) is a no-op in the SDK but the wasted
  # allocation hurts the hot path.
  def counter(name, unit: nil, description: nil)
    instruments[[:counter, name]] ||= meter.create_counter(name, unit: unit, description: description)
  end

  def histogram(name, unit: nil, description: nil)
    instruments[[:histogram, name]] ||= meter.create_histogram(name, unit: unit, description: description)
  end

  # Shortcut for `Telemetry.tracer.in_span(name, ...) { ... }`. Yields
  # the span so the block can decorate with attributes / record
  # errors. With OTel off, a NoopSpan is yielded and the block still
  # runs.
  def in_span(name, attributes: nil, &)
    tracer.in_span(name, attributes: attributes, &)
  end

  # Emit an OTel log record correlated with whatever span context is
  # currently active. No-op when OTel is off.
  def log_event(body, severity: :info, attributes: nil)
    return unless enabled?

    logger.on_emit(
      timestamp:       Time.current,
      severity_text:   severity.to_s.upcase,
      severity_number: severity_number_for(severity),
      body:            body,
      attributes:      attributes,
      context:         OpenTelemetry::Context.current
    )
  end

  def instruments
    @instruments ||= {}
  end

  # OTel severity numbers: DEBUG=5, INFO=9, WARN=13, ERROR=17, FATAL=21.
  # See the OTel logs data model spec.
  def severity_number_for(severity)
    # rubocop:disable Lint/DuplicateBranch
    # `else 9` is *intentionally* the same as the :info branch -- any
    # unknown severity defaults to INFO. Spelling it out keeps the
    # mapping table readable.
    case severity.to_sym
    when :debug then 5
    when :info  then 9
    when :warn  then 13
    when :error then 17
    when :fatal then 21
    else 9
    end
    # rubocop:enable Lint/DuplicateBranch
  end

  # ---- No-op shims used when the SDK isn't loaded ------------------
  # Mirror only the surface the app actually calls. Anything we don't
  # use stays unimplemented -- adding it later is cheap if a call site
  # grows.

  class NoopSpan
    def set_attribute(_key, _value); end
    def add_event(_name, **); end
    def record_exception(_exception, **); end
    def status=(_status); end
  end

  class NoopTracer
    def in_span(_name, **)
      yield NoopSpan.new
    end
  end

  class NoopInstrument
    def add(_value, attributes: nil); end
    def record(_value, attributes: nil); end
  end

  class NoopMeter
    def create_counter(_name, **_opts) = NoopInstrument.new
    def create_histogram(_name, **_opts) = NoopInstrument.new
    def create_up_down_counter(_name, **_opts) = NoopInstrument.new
  end

  class NoopLogger
    def on_emit(**); end
  end
end
