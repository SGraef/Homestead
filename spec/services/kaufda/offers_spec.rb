# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Kaufda::Offers do
  # Real-world fixture: a stripped-down version of what kaufDA's Aldi
  # Nord retailer page returns. Keeps the test self-contained while
  # mirroring the actual __NEXT_DATA__ structure.
  def page_html(items)
    next_data = {
      props: {
        pageProps: {
          pageInformation: {
            offers: { main: { items: items } }
          }
        }
      }
    }
    %(<html><head></head><body>) +
      %(<script id="__NEXT_DATA__" type="application/json">) +
      next_data.to_json +
      %(</script></body></html>)
  end

  describe ".pull_all" do
    it "extracts offers from the Geschaefte/<slug> page's __NEXT_DATA__" do
      stub_request(:get, "https://www.kaufda.de/Geschaefte/Aldi-Nord")
        .to_return(status: 200, body: page_html([
          { "id"            => "abc-123",
            "publisherName" => "ALDI Nord",
            "title"         => "Schinkengulasch",
            "description"   => "500 g Pkg.",
            "validFrom"     => "2026-05-04T00:00:00.000+0000",
            "validUntil"    => "2026-05-09T20:00:00.000+0000",
            "prices"        => { "mainPrice" => 2.99, "secondaryPrice" => 3.89 },
            "offerImages"   => { "url" => { "normal" => "https://x/y.jpg" } } }
        ]))

      results = described_class.pull_all
      expect(results.size).to eq(1)
      o = results.first
      expect(o.external_id).to eq("abc-123")
      expect(o.title).to eq("Schinkengulasch")
      expect(o.retailer_name).to eq("ALDI Nord")
      expect(o.retailer_slug).to eq("aldi-nord")
      expect(o.price_cents).to eq(299)
      expect(o.regular_price_cents).to eq(389)  # secondaryPrice > mainPrice
      expect(o.image_url).to eq("https://x/y.jpg")
      expect(o.valid_until).to eq(Date.new(2026, 5, 9))
    end

    it "ignores secondaryPrice when it isn't strictly higher than mainPrice" do
      stub_request(:get, "https://www.kaufda.de/Geschaefte/Aldi-Nord")
        .to_return(status: 200, body: page_html([
          { "id" => "x", "title" => "Brot", "publisherName" => "ALDI Nord",
            "prices" => { "mainPrice" => 1.50, "secondaryPrice" => 1.50 } }
        ]))
      expect(described_class.pull_all.first.regular_price_cents).to be_nil
    end

    it "drops malformed rows without raising" do
      stub_request(:get, "https://www.kaufda.de/Geschaefte/Aldi-Nord")
        .to_return(status: 200, body: page_html([
          { "id" => nil, "title" => "no id",   "prices" => { "mainPrice" => 1.0 } },
          { "id" => "1", "title" => "no price" },
          { "id" => "2", "prices" => { "mainPrice" => 1.0 } },           # no title
          { "id" => "3", "title" => "ok", "prices" => { "mainPrice" => 0.50 },
            "publisherName" => "X" }
        ]))
      expect(described_class.pull_all.map(&:external_id)).to eq(["3"])
    end

    it "honours an explicit `retailers:` argument and the env override" do
      stub_request(:get, "https://www.kaufda.de/Geschaefte/Action")
        .to_return(status: 200, body: page_html([]))
      expect { described_class.pull_all(retailers: %w[Action]) }.not_to raise_error
      expect(WebMock).to have_requested(:get,
        "https://www.kaufda.de/Geschaefte/Action").at_least_once
      expect(WebMock).not_to have_requested(:get,
        "https://www.kaufda.de/Geschaefte/Aldi-Nord")
    end

    it "swallows network errors and returns []" do
      stub_request(:get, %r{www\.kaufda\.de}).to_timeout
      expect(described_class.pull_all).to eq([])
    end

    it "returns [] when the page has no __NEXT_DATA__ block" do
      stub_request(:get, %r{www\.kaufda\.de}).to_return(status: 200, body: "<html><body>oops</body></html>")
      expect(described_class.pull_all).to eq([])
    end
  end
end
