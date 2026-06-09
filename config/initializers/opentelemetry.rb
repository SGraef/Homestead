# frozen_string_literal: true
# typed: ignore

# OpenTelemetry instrumentation. Three signals: traces, metrics, logs.
#
# Disabled by default. Set OTEL_EXPORTER_OTLP_ENDPOINT to a reachable
# OTLP collector URL (gRPC `http://...:4317` or HTTP/protobuf
# `http://...:4318`) and the SDK boots on the next process start. With
# the env var unset we skip the entire bring-up: no exporter threads,
# no SDK gems loaded into memory, no overhead. See
# docs/OBSERVABILITY.md for the env-var reference and a local
# Collector docker-compose example.
#
# Why three SDKs:
#   * traces (`opentelemetry-sdk`) — GA. Auto-instrumentation covers
#     Rack, ActiveRecord, Net::HTTP, Faraday, Mysql2, Solid Queue, etc.
#   * metrics (`opentelemetry-metrics-sdk`) — GA. Custom instruments
#     for receipt OCR duration, line-items detected, synonym hit rate.
#   * logs (`opentelemetry-logs-sdk`) — experimental in the Ruby SDK
#     but functional. Pipes Rails' logger output through OTel so
#     traces / logs / metrics share the same correlated context.
return unless ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present? ||
              ENV["OTEL_ENABLED"] == "1"

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"
require "opentelemetry-metrics-sdk"
require "opentelemetry/exporter/otlp_metrics"
require "opentelemetry-logs-sdk"
require "opentelemetry/exporter/otlp_logs"

service_name    = ENV.fetch("OTEL_SERVICE_NAME", "pantria")
service_version = ENV.fetch("OTEL_SERVICE_VERSION",
                            ENV.fetch("GIT_SHA", "unknown"))
environment     = ENV.fetch("OTEL_DEPLOYMENT_ENVIRONMENT",
                            Rails.env.to_s)

OpenTelemetry::SDK.configure do |c|
  c.service_name    = service_name
  c.service_version = service_version

  # Resource attributes follow OTel semantic conventions. Anything
  # extra the user wants (k8s.pod.name, deployment.region, …) comes in
  # via OTEL_RESOURCE_ATTRIBUTES which the SDK merges automatically.
  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    "service.name"            => service_name,
    "service.version"         => service_version,
    "service.namespace"       => "pantria",
    "deployment.environment"  => environment,
    "process.runtime.name"    => "ruby",
    "process.runtime.version" => RUBY_VERSION
  )

  # Auto-instrumentation picks up every supported library that's
  # actually loaded in the process. Disable individual instrumentations
  # via OTEL_RUBY_INSTRUMENTATION_<NAME>_ENABLED=false (see the OTel
  # Ruby docs for the full list).
  c.use_all
end

# ---- Metrics ---------------------------------------------------------
# Periodic reader pushes metrics every 60s by default. Tune via
# OTEL_METRIC_EXPORT_INTERVAL (milliseconds).
OpenTelemetry.meter_provider.add_metric_reader(
  OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
    exporter: OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new
  )
)

# Built-in process/runtime metrics (GC, allocations) when the
# instrumentation lib registered an installer for them. The
# instrumentation-all bundle handles this automatically when present;
# this block is a no-op otherwise.
begin
  require "opentelemetry/instrumentation/process_runtime"
  OpenTelemetry::Instrumentation::ProcessRuntime::Instrumentation.instance.install({})
rescue LoadError
  # gem not present; skip.
end

# ---- Logs ------------------------------------------------------------
# Batch-processor + OTLP exporter. Pipes go through the LoggerProvider
# rather than through Rails.logger directly because the Logs API + SDK
# is still experimental in Ruby and Rails' logger chain has its own
# formatting / level gating we don't want to fight. App code that
# wants to emit an OTel-native log record calls Telemetry.log_event
# (see app/services/telemetry.rb).
OpenTelemetry.logger_provider.add_log_record_processor(
  OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(
    OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new
  )
)

Rails.logger.info(
  "[OpenTelemetry] enabled service=#{service_name} version=#{service_version} " \
  "env=#{environment} endpoint=#{ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT", "(from OTEL_* defaults)")}"
)
