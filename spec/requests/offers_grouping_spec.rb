# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "GET /offers — category grouping" do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }

  before do
    household
    login_via_post(user)
  end

  it "renders one section per category, with the no-category bucket last" do
    # Two offers in 'Milch & Käse', one in 'Tiefkühl', one uncategorised.
    create(:offer, household: household, external_id: "m1",
                   title: "Vollmilch 1L", category: "Milch & Käse",
                   valid_until: Date.current + 4)
    create(:offer, household: household, external_id: "m2",
                   title: "Camembert", category: "Milch & Käse",
                   valid_until: Date.current + 4)
    create(:offer, household: household, external_id: "t1",
                   title: "Tiefkühl-Pizza", category: "Tiefkühl",
                   valid_until: Date.current + 4)
    create(:offer, household: household, external_id: "o1",
                   title: "Brot", category: nil,
                   valid_until: Date.current + 4)

    get offers_path
    body = response.body

    headings = body.scan(%r{<h2[^>]*>(.+?)</h2>}m).flatten.map { |s| s.gsub(/<[^>]+>/, "").strip }
    # Both named categories appear as <h2> headings (case- and
    # entity-tolerant); a "no category" heading is the last one.
    expect(headings.find { |h| h.start_with?("Milch") }).not_to be_nil
    expect(headings.find { |h| h.start_with?("Tiefkühl") }).not_to be_nil
    expect(headings.last).to match(/Sonstige|Other/)

    # Member-count text surfaces somewhere on the page (the spans are
    # spread across lines, so anchor loosely on "(2 …)").
    expect(body).to match(/\(2[^)]*(Angebote|offers)\)/)

    # Order: named categories alphabetically, no-category last.
    milch_h    = headings.index { |h| h.start_with?("Milch") }
    tiefkuhl_h = headings.index { |h| h.start_with?("Tiefkühl") }
    other_h    = headings.index { |h| h.match?(/Sonstige|Other/) }
    expect(milch_h).to be < tiefkuhl_h
    expect(tiefkuhl_h).to be < other_h
  end

  it "uses the linked product's category over the offer's own when both exist" do
    product = create(:product, household: household, name: "Joghurt",
                                category: "Joghurt-Curated")
    create(:offer, household: household, external_id: "x1",
                   title: "Naturjoghurt 500g", category: "Milch & Käse",
                   product: product, valid_until: Date.current + 3)

    get offers_path
    expect(response.body).to include("Joghurt-Curated")
    headings = response.body.scan(%r{<h2[^>]*>(.+?)</h2>}m).flatten
                          .map { |s| s.gsub(/<[^>]+>/, "").strip }
    expect(headings).to include(a_string_starting_with("Joghurt-Curated"))
    expect(headings).not_to include(a_string_starting_with("Milch & Käse"))
  end
end
