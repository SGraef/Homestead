# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ProductSynonym do
  describe ".normalize" do
    it "lowercases, strips punctuation, collapses whitespace" do
      expect(described_class.normalize("Milch 1L")).to        eq("milch 1l")
      expect(described_class.normalize("MILCH-1L")).to        eq("milch 1l")
      expect(described_class.normalize("  milch   1L  ")).to  eq("milch 1l")
      expect(described_class.normalize("Bio · Milch (1L)")).to eq("bio milch 1l")
    end

    it "returns blank for blank / nil input" do
      expect(described_class.normalize(nil)).to eq("")
      expect(described_class.normalize("")).to  eq("")
      expect(described_class.normalize("    ")).to eq("")
    end

    it "normalizes Unicode (NFKC) so half-width digits fold to the canonical form" do
      expect(described_class.normalize("Milch １L")).to eq("milch 1l")
    end
  end

  describe "auto-populated normalized_term" do
    let(:product) { create(:product, name: "Milch") }

    it "sets normalized_term from term before validation" do
      syn = product.product_synonyms.create!(term: "MILCH 1L ALDI")
      expect(syn.normalized_term).to eq("milch 1l aldi")
    end

    it "is unique per product" do
      product.product_synonyms.create!(term: "MILCH 1L")
      dup = product.product_synonyms.build(term: "milch-1l")
      expect(dup).not_to be_valid
      expect(dup.errors[:normalized_term]).to be_present
    end

    it "allows the same synonym on different products" do
      other = create(:product, name: "Other product")
      product.product_synonyms.create!(term: "Milch 1L")
      expect(other.product_synonyms.build(term: "Milch 1L")).to be_valid
    end
  end
end
