# Observability

Pantria ships an OpenTelemetry instrumentation layer for **traces, metrics
and logs**. It is **off by default**: until you set
`OTEL_EXPORTER_OTLP_ENDPOINT`, the SDK is not loaded, no exporter threads
are spawned, and the in-process `Telemetry` helpers fall back to zero-cost
no-op shims. CI runs and local dev incur no telemetry overhead.

## Quick start

Point Pantria at any OTLP-compatible endpoint — a local
[Collector](https://opentelemetry.io/docs/collector/), Grafana Cloud,
Honeycomb, Datadog (via the Collector), Tempo + Mimir + Loki, etc.

```bash
# gRPC (default port 4317)
export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317

# OR HTTP/protobuf (default port 4318)
export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

Restart the Rails (and Solid Queue worker) containers. You should see one
log line at boot:

```
[OpenTelemetry] enabled service=pantria version=... env=production endpoint=...
```

## Env var reference

| Variable                              | Purpose                                                                                     | Default                          |
| ------------------------------------- | ------------------------------------------------------------------------------------------- | -------------------------------- |
| `OTEL_EXPORTER_OTLP_ENDPOINT`         | OTLP collector URL. **Setting this enables the SDK.**                                       | unset (= disabled)               |
| `OTEL_ENABLED`                        | `"1"` to force-enable even without an endpoint (debugging the no-op path)                   | unset                            |
| `OTEL_EXPORTER_OTLP_PROTOCOL`         | `grpc` or `http/protobuf`                                                                   | `grpc`                           |
| `OTEL_EXPORTER_OTLP_HEADERS`          | Comma-separated `key=value` pairs (auth headers, tenant ids)                                | unset                            |
| `OTEL_SERVICE_NAME`                   | Service name in spans / metrics / logs                                                      | `pantria`                        |
| `OTEL_SERVICE_VERSION`                | Reported as `service.version`                                                               | `GIT_SHA` env, then `"unknown"`  |
| `OTEL_DEPLOYMENT_ENVIRONMENT`         | Reported as `deployment.environment`                                                        | `Rails.env`                      |
| `OTEL_RESOURCE_ATTRIBUTES`            | Extra resource attrs, `key=value,key=value` (k8s.pod.name, region, ...)                     | unset                            |
| `OTEL_METRIC_EXPORT_INTERVAL`         | Push interval in ms                                                                         | 60000                            |
| `OTEL_RUBY_INSTRUMENTATION_<NAME>_ENABLED` | Disable individual auto-instrumentations (e.g. `..._NET_HTTP_ENABLED=false`)            | enabled                          |

The full list lives in the
[OTel SDK spec](https://opentelemetry.io/docs/specs/otel/configuration/sdk-environment-variables/).

## What ships out of the box

**Traces** — auto-instrumentation for Rack, Rails (controllers, view
rendering, ActiveRecord), Net::HTTP, Faraday, MySQL2, Solid Queue,
Active Job, Sidekiq (if you swap), Redis, GraphQL, … plus custom spans at:

- `receipt_scanner.call` — OCR → Parser pipeline. Attributes:
  raw text length, line items detected, detected total.
- `receipt_confirmer.call` — confirm action. Attributes: receipt id,
  household id, line counts per action (create / match / skip).
- `bring.pull` — Bring → Pantria sync. Attributes: added /
  reactivated / marked_purchased / unchanged counts.

**Metrics** — Rack request duration histograms via auto-instrumentation,
plus app-defined:

| Name                                            | Kind      | Unit | What                                                            |
| ----------------------------------------------- | --------- | ---- | --------------------------------------------------------------- |
| `pantria.receipt_scanner.duration_ms`           | histogram | ms   | Image → parsed `Result` end-to-end                              |
| `pantria.receipt_scanner.line_items_detected`   | counter   | —    | Line items the parser pulled out                                |
| `pantria.receipt_scanner.empty_ocr_total`       | counter   | —    | Receipts whose OCR returned no text at all                      |
| `pantria.receipts.confirmed_total`              | counter   | —    | Receipts the user confirmed                                     |
| `pantria.synonyms.created_total`                | counter   | —    | ProductSynonym rows promoted from a confirm                     |
| `pantria.bring.pull_total`                      | counter   | —    | Bring → Pantria pulls (every 5min by default)                   |
| `pantria.bring.items_synced_total`              | counter   | —    | Grocery rows touched by a pull (added + reactivated + purchased) |

**Logs** — high-signal application events via `Telemetry.log_event(...)`.
Rails' default logger is unchanged — its output still lands in stdout / the
file logger / wherever. The OTel logs SDK is currently
[experimental in Ruby](https://github.com/open-telemetry/opentelemetry-ruby/issues),
so the bridge is opt-in: call `Telemetry.log_event` from app code where you
want a structured, span-correlated log record exported separately.

## Local Collector with docker-compose

Drop this into `docker-compose.observability.yml` and run with
`docker compose -f docker-compose.yml -f docker-compose.observability.yml up`:

```yaml
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.110.0
    command: ["--config=/etc/otel-collector.yaml"]
    volumes:
      - ./otel-collector.yaml:/etc/otel-collector.yaml:ro
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
      - "8888:8888"   # Collector's own metrics
    restart: unless-stopped

  web:
    environment:
      OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector:4317"
      OTEL_SERVICE_NAME: "pantria"
  worker:
    environment:
      OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector:4317"
      OTEL_SERVICE_NAME: "pantria-worker"
```

Minimal `otel-collector.yaml` that prints to stdout (great for sanity
checking the wire format before you bolt on a real backend):

```yaml
receivers:
  otlp:
    protocols:
      grpc: { endpoint: 0.0.0.0:4317 }
      http: { endpoint: 0.0.0.0:4318 }

exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    traces:  { receivers: [otlp], exporters: [debug] }
    metrics: { receivers: [otlp], exporters: [debug] }
    logs:    { receivers: [otlp], exporters: [debug] }
```

## Adding instrumentation in app code

```ruby
# A span around a unit of work. The block's return value is also the
# span's return value. Use this for high-signal operations (long
# external calls, multi-step state machines) where the trace tree
# would otherwise show only the Rack span.
Telemetry.in_span("offer.sync_one", attributes: { "pantria.household.id" => h.id }) do |span|
  result = OfferSyncer.new(h).call
  span.set_attribute("pantria.offers.fetched", result.count)
  result
end

# A counter. Cached by name — call sites can construct it freely.
Telemetry.counter("pantria.receipts.uploaded_total").add(1, attributes: { "source" => "imap" })

# A histogram (durations, sizes).
Telemetry.histogram("pantria.bring.push_ms", unit: "ms").record(duration_ms)

# A structured log line correlated with the current span.
Telemetry.log_event("Bring rejected the token (HTTP 401)",
                    severity: :warn,
                    attributes: { "bring.connection.id" => @connection.id })
```

When OTel is off these are all zero-cost no-ops, so the call sites can
ship unconditionally.

## Performance notes

- The auto-instrumentation lib registers ~60 patches on app boot. With
  OTel **off** the gem isn't loaded and no patches register. With OTel
  **on** the patches add ~1-2% to request wall-clock per
  [official benchmarks](https://github.com/open-telemetry/opentelemetry-ruby/tree/main/test).
- The OTLP exporter batches in a background thread. A collector that
  goes down does NOT block your requests — failed exports drop with a
  warning and retry on the next batch.
- Disabling a noisy instrumentation (e.g. `Net::HTTP` if you have lots
  of internal traffic) is one env var: `OTEL_RUBY_INSTRUMENTATION_NET_HTTP_ENABLED=false`.
