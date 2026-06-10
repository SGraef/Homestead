# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ReceiptScanner::Parser do
  describe ".parse" do
    subject(:result) { described_class.parse(raw) }

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
    subject(:items) { described_class.parse(raw).line_items.map(&:name) }

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

  describe "real-world ALDI receipt (currency + digit tax codes + OCR noise)" do
    # Lifted from an actual photo of a German ALDI receipt. The OCR
    # returns digit / `|` tax codes (1, 2 = full / reduced VAT) with
    # a `€` between the price and the code, plus quantity-hint
    # continuation lines ("_ 4x 1,28"). Used to be a single-line
    # detection because the previous LINE_ITEM_RE didn't tolerate the
    # currency token in the tail.
    subject(:items) { described_class.parse(raw).line_items.map(&:name) }

    let(:raw) { <<~OCR }
      ALDI
      Niedernstraße 9 c, 24589 Nortorf

      ALLERGIKERKISSEN 9,99 € 2
      _ 4x 1,28
      NATURLAND BIO H-MILCH 3,00 € |
      SCHWEPPES BITTERGETRAN 2,18€ 2
      2x 0,29
      PFANDWERT 0,25 0,50 € 2
      WETSSKASE IN SALZLAKE 6,99 € |
      WETZENMEHL 1,18 € 1
      JOGHURT NACH GRIECH, A 2,19 € 1
      NATURLAND BIO FRUCHTMA 1,15 €1
      NL BIO APFELMUS 3606 0,75 € 1
      ERDBEERKONFI TURE 1,59 € 1
      KONFITÜRE 4508 1,79€ 1
      HAHN. SCHENKELSTEAKS - 3,99 € |
      TK BIO-GEMUSEPFANNE 2,49 € |
      KNABBERSTICKS QS 90g 1,69 € 1
      ALMETTE 0°99 ¢ 7
      ZU ZAHLEN 113,73 €
      Kartenzahlung
    OCR

    it "extracts the obvious product lines that used to fail (≥ 10)" do
      expect(items.size).to be >= 10
    end

    it "handles `€ <digit>` (full VAT) and `€ |` (OCR-mis-read 1) tax tails" do
      expect(items).to include("ALLERGIKERKISSEN",
                               "NATURLAND BIO H-MILCH",
                               "WETZENMEHL")
    end

    it "drops quantity-hint continuation lines (`_ 4x 1,28`)" do
      expect(items).not_to include(a_string_matching(/\A_? ?\d+x/))
    end

    it "recovers from common OCR misreads in the price area (`0°99 ¢` → 0,99 €)" do
      expect(items).to include("ALMETTE")
    end

    it "stops at the total line (no products from below ZU ZAHLEN)" do
      expect(items.join("|")).not_to include("Kartenzahlung")
    end
  end
end
