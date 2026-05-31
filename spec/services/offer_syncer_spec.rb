# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe OfferSyncer do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user, postal_code: "10115") }

  # Stub all three default industry endpoints. By default the named slugs
  # return whatever `supermaerkte_results` is set to; the others return [].
  def stub_industries(supermaerkte: [], discounter: [], drogerie: [])
    stub_request(:get, %r{api\.marktguru\.de/api/v1/industries/supermaerkte/offers})
      .to_return(status: 200, body: { results: supermaerkte }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{api\.marktguru\.de/api/v1/industries/discounter/offers})
      .to_return(status: 200, body: { results: discounter }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{api\.marktguru\.de/api/v1/industries/drogerie-gesundheit/offers})
      .to_return(status: 200, body: { results: drogerie }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  # Default kaufDA stub — empty page, so the syncer's kaufDA branch is
  # exercised without polluting Marktguru-focused tests.
  def stub_kaufda(retailers: { "Aldi-Nord" => [] })
    retailers.each do |slug, items|
      next_data = { props: { pageProps: { pageInformation: { offers: { main: { items: items } } } } } }
      html = "<html><script id=\"__NEXT_DATA__\" type=\"application/json\">#{next_data.to_json}</script></html>"
      stub_request(:get, "https://www.kaufda.de/Geschaefte/#{slug}")
        .to_return(status: 200, body: html)
    end
  end

  before do
    stub_kaufda
    # MeinProspekt search API is stubbed to empty by default so unrelated
    # tests are not affected; opt-in per spec when relevant.
    allow(MeinProspekt::Offers).to receive(:pull_all).and_return([])
    # OFF categorizer fallback would otherwise hit the live API on
    # every blank-category offer. Returning nil keeps existing
    # assertions stable while exercising the syncer call path.
    allow(OfferCategorizer).to receive(:classify).and_return(nil)
  end

  it "creates an Offer for every upstream hit, with or without a known product" do
    create(:product, household: household, name: "Vollmilch")
    create(:store,   household: household, name: "REWE")

    stub_industries(supermaerkte: [
                      { "id" => 1001, "description" => "je 1 L",
                        "product"  => { "name" => "Bio Vollmilch 1L" },
                        "retailer" => { "name" => "REWE", "uniqueName" => "rewe" },
                        "price" => 0.89, "oldPrice" => 1.19,
                        "validTo" => (Date.current + 4).iso8601 }
                    ], discounter: [
                      { "id" => 1002, "description" => "je 1 Stk",
                        "product"  => { "name" => "Tiefkühl-Pizza Salami" },
                        "retailer" => { "name" => "Lidl" },
                        "price" => 2.49,
                        "validTo" => (Date.current + 2).iso8601 }
                    ])

    described_class.new(household).call

    matched = household.offers.find_by(external_id: "1001")
    untrack = household.offers.find_by(external_id: "1002")

    expect(matched.product&.name).to eq("Vollmilch")
    expect(matched.store&.name).to   eq("REWE")
    expect(untrack.product).to       be_nil
    expect(untrack.store).to         be_nil
  end

  it "prefers the longest-name product when multiple substrings match" do
    create(:product, household: household, name: "Milch")
    create(:product, household: household, name: "Bio Vollmilch")

    stub_industries(supermaerkte: [
                      { "id" => 7, "description" => "je 1 L",
                        "product"  => { "name" => "Bio Vollmilch 1L Alnatura" },
                        "retailer" => { "name" => "REWE" },
                        "price" => 0.99,
                        "validTo" => (Date.current + 1).iso8601 }
                    ])

    described_class.new(household).call
    expect(household.offers.last.product.name).to eq("Bio Vollmilch")
  end

  it "is idempotent: re-running updates instead of duplicating" do
    body = [
      { "id" => 2002, "description" => "je 1 L",
        "product"  => { "name" => "Bio Vollmilch 1L" },
        "retailer" => { "name" => "REWE" },
        "price" => 0.99,
        "validTo" => (Date.current + 3).iso8601 }
    ]
    stub_industries(supermaerkte: body)
    described_class.new(household).call

    body[0]["price"] = 0.79
    stub_industries(supermaerkte: body)
    result = described_class.new(household).call

    expect(household.offers.count).to eq(1)
    expect(result.created).to eq(0)
    expect(result.updated).to eq(1)
    expect(household.offers.first.price_cents).to eq(79)
  end

  it "is a no-op when the household has no postal code" do
    household.update!(postal_code: nil)
    expect(described_class.new(household).call).to be_nil
    expect(WebMock).not_to have_requested(:get, /marktguru/)
  end

  it "sweeps offers whose valid_until is in the past" do
    create(:offer, household: household, external_id: "old-1",
                   valid_until: Date.current - 1)
    stub_industries  # all three return []

    expect { described_class.new(household).call }
      .to change(household.offers, :count).by(-1)
  end

  it "skips offers whose retailer is not in the household's allow-list" do
    household.offer_retailer_filters.create!(retailer: "REWE")

    stub_industries(supermaerkte: [
                      { "id" => 60, "description" => "1 L",
                        "product"  => { "name" => "Milch" },
                        "retailer" => { "name" => "REWE", "uniqueName" => "rewe" },
                        "price" => 0.89,
                        "validTo" => (Date.current + 2).iso8601 },
                      { "id" => 61, "description" => "1 L",
                        "product"  => { "name" => "Milch" },
                        "retailer" => { "name" => "Edeka", "uniqueName" => "edeka" },
                        "price" => 0.99,
                        "validTo" => (Date.current + 2).iso8601 }
                    ])

    described_class.new(household).call
    expect(household.offers.pluck(:external_id)).to eq(["60"])
  end

  it "still allows all retailers when the allow-list is empty (default)" do
    stub_industries(supermaerkte: [
                      { "id" => 70, "description" => "1 L",
                        "product"  => { "name" => "Milch" },
                        "retailer" => { "name" => "Aldi" },
                        "price" => 0.79,
                        "validTo" => (Date.current + 2).iso8601 }
                    ])

    described_class.new(household).call
    expect(household.offers.count).to eq(1)
  end

  it "merges kaufDA offers alongside Marktguru, distinguished by source" do
    stub_industries(supermaerkte: [
                      { "id" => 100, "description" => "1 L",
                        "product"  => { "name" => "Vollmilch" },
                        "retailer" => { "name" => "REWE" }, "price" => 0.89,
                        "validTo" => (Date.current + 3).iso8601 }
                    ])
    stub_kaufda(retailers: {
                  "Aldi-Nord" => [
                    { "id" => "kd-1", "title" => "Schinkengulasch",
                      "publisherName" => "ALDI Nord",
                      "validUntil" => (Date.current + 4).iso8601,
                      "prices" => { "mainPrice" => 2.99, "secondaryPrice" => 3.89 } }
                  ]
                })

    described_class.new(household).call

    sources = household.offers.pluck(:source).tally
    expect(sources).to eq("marktguru" => 1, "kaufda" => 1)
    aldi = household.offers.find_by(source: "kaufda", external_id: "kd-1")
    expect(aldi.title).to eq("Schinkengulasch")
    expect(aldi.price_cents).to eq(299)
    expect(aldi.regular_price_cents).to eq(389)
    expect(aldi.retailer_name).to eq("ALDI Nord")
  end

  it "backfills the offer's category from OfferCategorizer when blank" do
    stub_industries  # Marktguru returns nothing
    stub_kaufda(retailers: { "Aldi-Nord" => [
                  { "id" => "kdb-1", "title" => "Bio Vollmilch 1L",
                    "publisherName" => "ALDI Nord",
                    "validUntil" => (Date.current + 4).iso8601,
                    "prices" => { "mainPrice" => 0.99 } }
                ] })
    allow(OfferCategorizer).to receive(:classify)
      .with("Bio Vollmilch 1L", household: household).and_return("Milchprodukte")

    described_class.new(household).call

    expect(household.offers.find_by(external_id: "kdb-1").category)
      .to eq("Milchprodukte")
  end

  it "does NOT touch a category the adapter already set (Marktguru industry)" do
    stub_industries(supermaerkte: [
                      { "id" => 999, "description" => "1 L",
                        "product" => { "name" => "Milch" },
                        "retailer" => { "name" => "REWE" },
                        "price" => 0.89,
                        "validTo" => (Date.current + 2).iso8601 }
                    ])
    # Default before-hook stubs classify → nil. Override the
    # expectation explicitly: it must not even be called.
    expect(OfferCategorizer).not_to receive(:classify)

    described_class.new(household).call

    # Marktguru's adapter stamps category = industry slug ("supermaerkte").
    expect(household.offers.find_by(external_id: "999").category)
      .to eq("supermaerkte")
  end

  it "skips offers whose title matches a blocklist entry" do
    household.offer_blocklist_entries.create!(pattern: "Katzenfutter")

    stub_industries(supermaerkte: [
                      { "id" => 50, "description" => "1 kg",
                        "product"  => { "name" => "Whiskas Katzenfutter" },
                        "retailer" => { "name" => "REWE" }, "price" => 1.99,
                        "validTo" => (Date.current + 2).iso8601 },
                      { "id" => 51, "description" => "1 L",
                        "product"  => { "name" => "Vollmilch" },
                        "retailer" => { "name" => "REWE" }, "price" => 0.89,
                        "validTo" => (Date.current + 2).iso8601 }
                    ])

    described_class.new(household).call
    expect(household.offers.pluck(:external_id)).to eq(["51"])
  end
end
