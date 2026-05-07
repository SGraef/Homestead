# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ReceiptScanner::Parser do
  describe ".parse" do
    let(:raw) { <<~OCR }
      REWE
      Hauptstr. 12
      99999 Berlin

      Vollmilch 1L          1,19 A
      Bio Eier 6er          2,99 A
      2 x Brötchen          1,80
      MwSt 7%               0,38
      SUMME EUR             5,98
      01.05.2026 12:34
    OCR

    subject(:result) { described_class.parse(raw) }

    it "detects the store from the header" do
      expect(result.store_name).to eq("REWE")
    end

    it "detects the purchase date" do
      expect(result.purchased_on).to eq(Date.new(2026, 5, 1))
    end

    it "detects the total in cents" do
      expect(result.subtotal_cents).to eq(598)
    end

    it "extracts plausible line items and skips MwSt / total" do
      names = result.line_items.map(&:name)
      expect(names).to include("Vollmilch 1L", "Bio Eier 6er", "Brötchen")
      expect(names).not_to include(a_string_matching(/MwSt|SUMME/))
    end

    it "parses quantities prefixing the name" do
      brot = result.line_items.find { |li| li.name == "Brötchen" }
      expect(brot.quantity).to eq(2)
      expect(brot.total_cents).to eq(180)
    end
  end

  describe "filtering of total/tax/payment lines" do
    let(:raw) { <<~OCR }
      REWE Markt
      Hauptstr. 12

      Vollmilch          1,19 A
      Brot               2,49 B
      Zwischensumme      3,68
      Endbetrag EUR      3,68
      A 19% MwSt         0,28
      B  7% MwSt         0,16
      Mehrwertsteuer     0,44
      Bar                5,00
      Wechselgeld        1,32
      EC-Karte           3,68
      Kassen-Nr 12345
      01.05.2026 12:34
    OCR

    subject(:items) { described_class.parse(raw).line_items.map(&:name) }

    it "keeps the actual products" do
      expect(items).to include("Vollmilch", "Brot")
    end

    it "drops every total / tax / payment / footer line" do
      forbidden = %w[
        Zwischensumme Endbetrag MwSt Mehrwertsteuer
        Bar Wechselgeld EC-Karte Kassen-Nr
      ]
      forbidden.each do |word|
        expect(items.join(" | ")).not_to include(word),
          "expected line items to NOT contain '#{word}', got: #{items.inspect}"
      end
    end

    it "still detects the total at the Endbetrag line" do
      result = described_class.parse(raw)
      expect(result.subtotal_cents).to eq(368)
    end
  end
end
