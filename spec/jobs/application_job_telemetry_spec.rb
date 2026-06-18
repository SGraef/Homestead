# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ApplicationJob do
  let(:runs)      { instance_double(Telemetry::NoopInstrument, add: nil) }
  let(:durations) { instance_double(Telemetry::NoopInstrument, record: nil) }

  before do
    # Within this scoped example group the only counter/histogram calls come
    # from ApplicationJob's around_perform, so stubbing unconditionally is safe
    # and sidesteps RSpec keyword-arg matching quirks.
    allow(Telemetry).to receive_messages(counter: runs, histogram: durations)
    allow(Telemetry).to receive(:log_event)
  end

  describe "source derivation" do
    [
      %w[BringPullProbeJob bring],
      %w[SyncOffersProbeJob offers],
      %w[CalendarPushProbeJob calendar], # calendar wins over push
      %w[DeliverPushProbeJob push],
      %w[PollInboundProbeJob inbound_email],
      %w[WidgetProbeJob other]
    ].each do |class_name, source|
      it "maps #{class_name} -> #{source}" do
        stub_const(class_name, Class.new(ApplicationJob) { def perform; end })
        class_name.constantize.perform_now
        expect(runs).to have_received(:add)
          .with(1, attributes: hash_including("source" => source, "job" => class_name))
      end
    end
  end

  it "records a success run + duration" do
    stub_const("OkProbeJob", Class.new(ApplicationJob) { def perform; end })
    OkProbeJob.perform_now

    expect(runs).to have_received(:add).with(1, attributes: hash_including("outcome" => "success"))
    expect(durations).to have_received(:record)
      .with(kind_of(Numeric), attributes: hash_including("outcome" => "success"))
  end

  it "records an error run, surfaces a failure log event, and re-raises" do
    stub_const("BoomProbeJob", Class.new(ApplicationJob) { def perform = raise("boom") })

    expect { BoomProbeJob.perform_now }.to raise_error(RuntimeError, "boom")

    expect(runs).to have_received(:add)
      .with(1, attributes: hash_including("outcome" => "error", "error.class" => "RuntimeError"))
    expect(Telemetry).to have_received(:log_event)
      .with(/background job failed: BoomProbeJob/, severity: :error, attributes: anything)
  end
end
