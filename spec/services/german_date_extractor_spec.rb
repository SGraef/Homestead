# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe GermanDateExtractor do
  let(:ref) { Date.new(2026, 6, 15) } # a Monday

  def extract(text) = described_class.call(text, reference: ref)

  describe "positive cases" do
    it "parses 'am 5. Mai um 14 Uhr' (rolls to next year — May has passed)" do
      s = extract("Termin am 5. Mai um 14 Uhr")
      expect(s.date).to eq(Date.new(2027, 5, 5))
      expect([s.hour, s.min]).to eq([14, 0])
      expect(s.title).to eq("Termin")
    end

    it "parses 'am 20. Juni' later this year as all-day" do
      s = extract("Treffen am 20. Juni")
      expect(s.date).to eq(Date.new(2026, 6, 20))
      expect(s.all_day?).to be(true)
    end

    it "parses dd.mm.yyyy" do
      expect(extract("bis 05.07.2026 abgeben").date).to eq(Date.new(2026, 7, 5))
    end

    it "parses relative words" do
      expect(extract("morgen anrufen").date).to eq(ref + 1)
      expect(extract("übermorgen").date).to eq(ref + 2)
      expect(extract("heute erledigen").date).to eq(ref)
    end

    it "parses the next weekday" do
      expect(extract("nächsten Dienstag").date).to eq(Date.new(2026, 6, 16))
    end

    it "parses an HH:MM time alongside a date" do
      expect(extract("am 20. Juni 09:30").then { |s| [s.hour, s.min] }).to eq([9, 30])
    end
  end

  describe "negative cases (precision over recall)" do
    ["ich habe 5 Äpfel gekauft", "Seite 14", "5 Minuten", "14 Uhr", "nichts geplant"].each do |text|
      it "returns nil for #{text.inspect}" do
        expect(extract(text)).to be_nil
      end
    end
  end
end
