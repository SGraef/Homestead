# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe SyncGroceryToBringJob do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  context "when Bring is not connected" do
    it "no-ops" do
      expect_any_instance_of(Bring::Client).not_to receive(:push_item)
      described_class.perform_now(household.id, action: "push", name: "Milk")
    end
  end

  context "when Bring is connected" do
    let!(:connection) do
      BringConnection.create!(
        household:               household,
        bring_email:             "demo@example.com",
        bring_user_uuid:         "u-1",
        default_list_uuid:       "l-1",
        access_token:            "tok",
        refresh_token:           "r",
        access_token_expires_at: 1.hour.from_now,
        country_code:            "DE"
      )
    end

    it "pushes via the client and stamps last_synced_at" do
      stub_request(:put, %r{api\.getbring\.com/rest/v2/bringlists/l-1})
        .to_return(status: 204)

      described_class.perform_now(household.id, action: "push", name: "Vollmilch")

      expect(connection.reload.last_synced_at).to be_within(2.seconds).of(Time.current)
      expect(connection.last_error).to be_nil
    end

    it "records the error message and re-raises on a transient failure" do
      stub_request(:put, %r{api\.getbring\.com/rest/v2/bringlists/l-1})
        .to_return(status: 502)
      # retry_on uses a per-exception executions counter; force it past
      # the limit so the error propagates instead of being scheduled for
      # retry, which would swallow it.
      allow_any_instance_of(described_class)
        .to receive(:executions_for).and_return(described_class::MAX_ATTEMPTS_FOR_TRANSIENT)

      expect {
        described_class.perform_now(household.id, action: "push", name: "Vollmilch")
      }.to raise_error(Bring::Error)

      expect(connection.reload.last_error).to be_present
    end

    it "discards (no retry) when Bring rejects the token" do
      stub_request(:put, %r{api\.getbring\.com/rest/v2/bringlists/l-1})
        .to_return(status: 401, body: "Unauthorized")

      # `discard_on Bring::AuthError` -- the job swallows the exception
      # so it doesn't re-enter the retry pipeline. We assert on the
      # side effects (connection state was updated, token survived).
      described_class.perform_now(household.id, action: "push", name: "Milk")

      expect(connection.reload.access_token).to eq("tok")
      expect(connection.last_error).to include("401")
    end
  end
end
