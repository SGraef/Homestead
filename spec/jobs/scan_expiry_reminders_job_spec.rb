# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ScanExpiryRemindersJob do
  it "delegates to the expiry scanner for the sole household" do
    allow(Reminders::ExpiryScanner).to receive(:run).and_return(3)
    expect(described_class.new.perform).to eq(3)
    expect(Reminders::ExpiryScanner).to have_received(:run)
  end
end
