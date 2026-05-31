# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe OfferCategorizer do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) } # auto-seeds defaults

  describe ".classify" do
    it "maps meat-cut titles to 'Fleisch & Wurst'" do
      expect(described_class.classify("Hähnchen Innenfilets", household: household))
        .to eq("Fleisch & Wurst")
    end

    it "maps sweets titles to 'Süßigkeiten'" do
      expect(described_class.classify("Saure Glühwürmchen", household: household))
        .to eq("Süßigkeiten")
      expect(described_class.classify("HARIBO Goldbären", household: household))
        .to eq("Süßigkeiten")
    end

    it "respects brand-precedence: 'Milka Tafel Vollmilch' → Süßigkeiten" do
      expect(described_class.classify("Milka Tafel Vollmilch", household: household))
        .to eq("Süßigkeiten")
    end

    it "is case-insensitive" do
      expect(described_class.classify("HÄHNCHEN", household: household))
        .to eq("Fleisch & Wurst")
    end

    it "returns nil when no keyword matches" do
      expect(described_class.classify("XYZ Random 42", household: household)).to be_nil
    end

    it "returns nil for blank / nil input" do
      expect(described_class.classify(nil,   household: household)).to be_nil
      expect(described_class.classify("",    household: household)).to be_nil
      expect(described_class.classify("   ", household: household)).to be_nil
    end

    it "returns nil when household is nil" do
      expect(described_class.classify("Vollmilch", household: nil)).to be_nil
    end

    it "honours per-household custom categories" do
      # Remove the seeded ones, install a single one called "Pet stuff".
      household.offer_categories.destroy_all
      cat = household.offer_categories.create!(name: "Pet stuff", position: 1)
      cat.offer_category_keywords.create!(keyword: "katzen")

      expect(described_class.classify("Katzenfutter Premium", household: household))
        .to eq("Pet stuff")
    end

    it "reads through the cache so freshly added keywords classify immediately" do
      # NOTE: Rails.cache = :null_store in test (config/environments/test.rb),
      # so this exercises the read-through path. With a real cache,
      # invalidation relies on `cache_key` including the latest
      # updated_at across categories + keywords.
      household.offer_categories.destroy_all
      cat = household.offer_categories.create!(name: "Test", position: 1)
      cat.offer_category_keywords.create!(keyword: "alpha")

      expect(described_class.classify("alpha thing", household: household)).to eq("Test")
      expect(described_class.classify("beta thing",  household: household)).to be_nil

      cat.offer_category_keywords.create!(keyword: "beta")
      expect(described_class.classify("beta thing", household: household)).to eq("Test")
    end
  end
end
