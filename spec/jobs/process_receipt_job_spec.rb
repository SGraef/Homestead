# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ProcessReceiptJob do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  let(:fake_outcome) do
    ReceiptScanner::Outcome.new(
      raw_text: "REWE\nMilk 1,19 A\nSUMME EUR 1,19\n",
      result:   ReceiptScanner::Result.new(
        store_name:     "REWE",
        purchased_on:   Date.new(2026, 5, 1),
        currency:       "EUR",
        subtotal_cents: 119,
        line_items:     [
          ReceiptScanner::LineItem.new(position: 1, line_text: "Milk 1,19 A",
                                       name: "Milk", quantity: 1.0,
                                       unit_price_cents: nil, total_cents: 119)
        ]
      )
    )
  end

  let(:receipt) do
    r = household.receipts.build(user: user)
    r.image.attach(
      io:           StringIO.new("fake-jpg"),
      filename:     "receipt.jpg",
      content_type: "image/jpeg"
    )
    r.save!
    r
  end

  it "writes raw OCR + parsed line items and moves status to parsed" do
    allow(ReceiptScanner).to receive(:call).and_return(fake_outcome)

    described_class.perform_now(receipt.id)

    receipt.reload
    expect(receipt.status).to eq("parsed")
    expect(receipt.detected_store_name).to eq("REWE")
    expect(receipt.purchased_on).to eq(Date.new(2026, 5, 1))
    expect(receipt.subtotal_cents).to eq(119)
    expect(receipt.receipt_line_items.count).to eq(1)
  end

  it "keeps the receipt pending and stores the error on a non-final failed attempt" do
    allow(ReceiptScanner).to receive(:call).and_raise(ReceiptScanner::OcrError, "boom")
    allow_any_instance_of(described_class).to receive(:executions).and_return(1)
    # `retry_on` consults a per-exception counter via `executions_for`,
    # which is independent of `executions`. Bypass it so the error
    # surfaces synchronously instead of being scheduled for retry.
    allow_any_instance_of(described_class).to receive(:executions_for).and_return(described_class::MAX_ATTEMPTS)

    expect { described_class.perform_now(receipt.id) }.to raise_error(ReceiptScanner::OcrError)

    receipt.reload
    expect(receipt.status).to eq("pending")
    expect(receipt.error_message).to include("boom")
  end

  it "marks the receipt failed once retries are exhausted" do
    allow(ReceiptScanner).to receive(:call).and_raise(ReceiptScanner::OcrError, "boom")
    allow_any_instance_of(described_class).to receive(:executions).and_return(described_class::MAX_ATTEMPTS)
    allow_any_instance_of(described_class).to receive(:executions_for).and_return(described_class::MAX_ATTEMPTS)

    expect { described_class.perform_now(receipt.id) }.to raise_error(ReceiptScanner::OcrError)

    receipt.reload
    expect(receipt.status).to eq("failed")
    expect(receipt.error_message).to include("boom")
  end

  it "rebuilds line items if a stale set existed before reprocessing" do
    receipt.update!(status: "pending")
    receipt.receipt_line_items.create!(parsed_name: "stale", parsed_total_cents: 1)
    allow(ReceiptScanner).to receive(:call).and_return(fake_outcome)

    described_class.perform_now(receipt.id)

    expect(receipt.reload.receipt_line_items.pluck(:parsed_name)).to eq(["Milk"])
  end
end
