# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Receipt do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:receipt)   { create(:receipt, household: household, user: user, status: "failed", error_message: "boom") }

  describe "#reprocessable?" do
    it "is false for confirmed receipts" do
      receipt.update!(status: "confirmed")
      expect(receipt.reprocessable?).to be false
    end

    it "is true for failed / parsed / pending receipts that still have an attachment" do
      %w[pending parsed failed].each do |s|
        receipt.update!(status: s)
        expect(receipt.reprocessable?).to be(true), "expected reprocessable? when status=#{s}"
      end
    end
  end

  describe "#reprocess!" do
    before do
      receipt.receipt_line_items.create!(parsed_name: "Milk", parsed_total_cents: 119)
      receipt.update!(detected_store_name: "REWE", purchased_on: Date.current,
                      subtotal_cents: 1234, parsed_at: Time.current, raw_text: "old")
    end

    it "wipes parsed state, drops line items and re-enqueues OCR" do
      expect do
        receipt.reprocess!
      end.to change { receipt.receipt_line_items.count }.from(1).to(0)
                                                        .and have_enqueued_job(ProcessReceiptJob).with(receipt.id)

      receipt.reload
      expect(receipt).to have_attributes(
        status:              "pending",
        raw_text:            nil,
        detected_store_name: nil,
        purchased_on:        nil,
        subtotal_cents:      nil,
        parsed_at:           nil,
        error_message:       nil
      )
    end
  end
end
