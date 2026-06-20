# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ProcessDocumentJob do
  let(:household) { create(:household, timezone: "UTC") }
  let(:adapter)   { instance_double(ReceiptScanner::Adapters::Tesseract, extract_text: ocr_text) }
  let(:ocr_text)  { "" }

  before { allow(ReceiptScanner).to receive(:adapter).and_return(adapter) }

  def today = Time.find_zone("UTC").today

  context "with a receipt" do
    let(:document) { create(:document, :receipt, household: household) }

    it "skips OCR and creates no reminder" do
      expect(adapter).not_to receive(:extract_text)
      expect { described_class.perform_now(document.id) }.not_to change(Todo, :count)
      expect(document.reload.due_on).to be_nil
    end
  end

  context "with a bill that states a due date" do
    let(:ocr_text)  { "Stadtwerke\nZahlbar bis 20.05.2026" }
    let(:document)  { create(:document, household: household, title: "Stromrechnung", kind: "bill") }

    it "extracts the due date and creates a reminder todo on the calendar" do
      expect { described_class.perform_now(document.id) }.to change(Todo, :count).by(1)

      document.reload
      expect(document.due_on).to eq(Date.new(2026, 5, 20))
      expect(document.due_on_detected).to be(true)

      todo = document.reminder_todos.first
      expect(todo.due_on).to eq(Date.new(2026, 5, 20))
      expect(todo.source).to eq("document")
      expect(todo.title).to include("Stromrechnung")
    end
  end

  context "with a bill that has no detectable date" do
    let(:ocr_text) { "Irgendein Brief ohne Datum" }
    let(:document) { create(:document, household: household, kind: "other") }

    it "falls back to a +1-week reminder" do
      described_class.perform_now(document.id)
      document.reload
      expect(document.due_on).to eq(today + 7)
      expect(document.due_on_detected).to be(false)
      expect(document.reminder_todos.first.due_on).to eq(today + 7)
    end
  end

  context "when re-run" do
    let(:ocr_text) { "Zahlbar bis 20.05.2026" }
    let(:document) { create(:document, household: household) }

    it "updates the single reminder and keeps an advanced status" do
      described_class.perform_now(document.id)
      todo = document.reminder_todos.first
      todo.transition_to("in_progress")

      expect { described_class.perform_now(document.id) }.not_to change(Todo, :count)
      expect(todo.reload.status).to eq("in_progress")
    end
  end

  context "when OCR fails" do
    let(:document) { create(:document, household: household, kind: "bill") }

    it "still creates a fallback reminder" do
      allow(adapter).to receive(:extract_text).and_raise(ReceiptScanner::OcrError, "tesseract blew up")
      expect { described_class.perform_now(document.id) }.to change(Todo, :count).by(1)
      expect(document.reload.due_on).to eq(today + 7)
    end
  end
end
