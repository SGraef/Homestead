# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Product, ".match_by_term" do
  let(:household) { create(:household) }
  let!(:milk)     { create(:product, household: household, name: "Milch") }
  let!(:other)    { create(:product, household: household, name: "Vollkornbrot") }

  it "matches by exact (case-insensitive) name" do
    expect(household.products.match_by_term("MILCH")).to include(milk)
    expect(household.products.match_by_term("milch")).to include(milk)
    expect(household.products.match_by_term("Milch")).to include(milk)
  end

  it "matches via a registered synonym, even with extra punctuation / case" do
    milk.product_synonyms.create!(term: "MILCH 1L ALDI")
    expect(household.products.match_by_term("milch-1l-aldi")).to include(milk)
    expect(household.products.match_by_term("Milch 1L Aldi")).to include(milk)
  end

  it "does not return cross-household products" do
    other_household = create(:household)
    other_milk      = create(:product, household: other_household, name: "Milch")
    expect(household.products.match_by_term("Milch")).to     include(milk)
    expect(household.products.match_by_term("Milch")).not_to include(other_milk)
  end

  it "returns an empty scope for blank input" do
    expect(household.products.match_by_term("")).to be_empty
    expect(household.products.match_by_term("   ")).to be_empty
    expect(household.products.match_by_term(nil)).to be_empty
  end

  it "does not match when there's neither a name match nor a synonym" do
    expect(household.products.match_by_term("Käse")).to be_empty
    expect(household.products.match_by_term("MILCH-1L")).to be_empty # no synonym yet
  end
end
