# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Documents::DueDateExtractor do
  let(:reference) { Date.new(2026, 1, 1) }

  def extract(text) = described_class.call(text, reference: reference)

  it "parses a numeric due date after 'fällig am'" do
    expect(extract("Rechnungsbetrag fällig am 14.03.2026")).to eq(Date.new(2026, 3, 14))
  end

  it "parses 'Zahlbar bis'" do
    expect(extract("Bitte begleichen. Zahlbar bis 01.04.2026.")).to eq(Date.new(2026, 4, 1))
  end

  it "parses 'Zahlungsziel'" do
    expect(extract("Zahlungsziel: 30.06.2026")).to eq(Date.new(2026, 6, 30))
  end

  it "parses a month-name date" do
    expect(extract("Fälligkeitsdatum 5. März 2026")).to eq(Date.new(2026, 3, 5))
  end

  it "parses an English 'Due date'" do
    expect(extract("Due date: 12.05.2026")).to eq(Date.new(2026, 5, 12))
  end

  it "prefers the due date over the invoice date" do
    text = "Rechnungsdatum 01.01.2026\nLeistung Januar\nZahlbar bis 15.01.2026"
    expect(extract(text)).to eq(Date.new(2026, 1, 15))
  end

  it "returns nil when no payment keyword is present" do
    expect(extract("Rechnungsdatum 01.01.2026, vielen Dank")).to be_nil
  end

  it "rejects a relative weekday after the keyword" do
    expect(extract("Betrag fällig am Montag")).to be_nil
  end

  it "returns nil for blank text" do
    expect(extract("")).to be_nil
  end
end
