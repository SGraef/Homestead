# frozen_string_literal: true
# typed: false

class ApplicationJob < ActiveJob::Base
  # Map a job class name to the integration "source" it serves so per-source
  # health (Bring / offers / calendar / push / inbound email) can be derived
  # from the job metrics without per-job configuration. First match wins — keep
  # "calendar" before "push" so CalendarPushJob is calendar, not push.
  SOURCE_PATTERNS = {
    /bring/i           => "bring",
    /offer/i           => "offers",
    /calendar/i        => "calendar",
    /reminder|expiry/i => "reminders",
    /push|deliver/i    => "push",
    /inbound|imap/i    => "inbound_email"
  }.freeze

  # Emit a span + run/duration/failure metrics around every job, so the silent
  # recurring jobs (Bring pull, IMAP poll, daily offers, calendar poll/push,
  # push delivery) surface success rate, latency and failures — and a failure
  # is logged as an OTel event, not just swallowed by the queue. No-op when OTel
  # is off (the Telemetry shims), so it's free in dev/test.
  around_perform do |job, block|
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    attrs   = {
      "job"    => job.class.name,
      "queue"  => job.queue_name.to_s,
      "source" => telemetry_source
    }

    Telemetry.in_span("job.perform", attributes: attrs) do |span|
      block.call
      record_job_run(attrs, "success", started)
    rescue StandardError => e
      mark_span_error(span, e)
      record_job_run(attrs, "error", started, error: e)
      Telemetry.log_event(
        "background job failed: #{job.class.name} (#{e.class}: #{e.message})",
        severity:   :error,
        attributes: attrs.merge("error.class" => e.class.name)
      )
      raise
    end
  end

  # Integration source this job serves (used as a metric dimension).
  def telemetry_source
    SOURCE_PATTERNS.each { |pattern, source| return source if self.class.name.match?(pattern) }
    "other"
  end

  private

  def record_job_run(attrs, outcome, started_at, error: nil)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round
    run_attrs   = attrs.merge("outcome" => outcome)
    run_attrs["error.class"] = error.class.name if error

    runs = Telemetry.counter("pantria.job.runs_total", description: "Background job runs by source and outcome")
    runs.add(1, attributes: run_attrs)

    durations = Telemetry.histogram("pantria.job.duration_ms", unit: "ms", description: "Background job duration")
    durations.record(duration_ms, attributes: attrs.merge("outcome" => outcome))
  end

  def mark_span_error(span, error)
    span.record_exception(error)
    return unless defined?(OpenTelemetry::Trace::Status)

    span.status = OpenTelemetry::Trace::Status.error("#{error.class}: #{error.message}")
  end
end
