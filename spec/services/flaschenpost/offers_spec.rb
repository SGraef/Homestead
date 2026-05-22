# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Flaschenpost::Offers do
  let(:warehouse_id) { 1 }

  let(:sitemap_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url><loc>https://www.flaschenpost.de/p/mio/mio-mio-mate-zero</loc></url>
      </urlset>
    XML
  end

  let(:product_html) do
    <<~HTML
      <!DOCTYPE html>
      <html><head>
      <script type="application/json" id="abc">{"pageType":{"productId":5648,"kind":"product"}}</script>
      </head></html>
    HTML
  end

  # Trimmed shape based on what flaschenpost's PDP actually returns.
  let(:pdp_response) do
    [
      {
        "id"     => "uuid-1",
        "key"    => "5648",
        "name"   => { "de-DE" => "Mio Mio Mate Zero" },
        "slug"   => { "de-DE" => "mio-mio-mate-zero" },
        "categories" => [{
          "obj" => {
            "name" => { "de-DE" => "Mate" },
            "custom" => { "type" => { "key" => "fp-category-subcategory" } },
            "ancestors" => [
              { "obj" => { "name" => { "de-DE" => "Mio" },        "custom" => { "type" => { "key" => "fp-category-brand"   } } } },
              { "obj" => { "name" => { "de-DE" => "Limo & Saft" }, "custom" => { "type" => { "key" => "fp-category"         } } } }
            ]
          }
        }],
        "masterVariant" => {
          "sku" => "8292",
          "price" => { "value" => { "centAmount" => 1299 } },
          "attributes" => [
            { "value" => "12 x 0,5L (Glas)" },
            { "value" => { "centAmount" => 779 } },
            { "value" => { "centAmount" => 1500 } } # higher tier -> regular price
          ],
          "images" => [{ "url" => "https://image.flaschenpost.de/p/mio.jpg" }]
        }
      }
    ]
  end

  before do
    Rails.cache.clear

    stub_request(:get, "https://www.flaschenpost.de/sitemap_p.xml")
      .to_return(status: 200, body: sitemap_xml, headers: { "Content-Type" => "application/xml" })

    stub_request(:get, "https://www.flaschenpost.de/p/mio/mio-mio-mate-zero")
      .to_return(status: 200, body: product_html, headers: { "Content-Type" => "text/html" })

    stub_request(:get, %r{www\.flaschenpost\.de/php-product-api/v1/products/pdp/warehouse/#{warehouse_id}})
      .to_return(status: 200, body: pdp_response.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  it "walks sitemap -> HTML -> PDP and returns OfferData" do
    offers = described_class.pull_all(warehouse_id: warehouse_id)
    expect(offers.size).to eq(1)

    o = offers.first
    expect(o).to have_attributes(
      external_id:         "5648",
      title:               "Mio Mio Mate Zero",
      brand:               "Mio",
      category:            "Limo & Saft",
      retailer_name:       "flaschenpost",
      retailer_slug:       "flaschenpost",
      price_cents:         1299,
      regular_price_cents: 1500,
      currency:            "EUR",
      quantity_text:       "12 x 0,5L (Glas)",
      image_url:           "https://image.flaschenpost.de/p/mio.jpg",
      source_url:          "https://www.flaschenpost.de/p/5648/mio-mio-mate-zero"
    )
  end

  it "no-ops when warehouse_id is nil or zero" do
    expect(described_class.pull_all(warehouse_id: nil)).to eq([])
    expect(described_class.pull_all(warehouse_id: 0)).to eq([])
  end

  it "memoises slug->productId resolution in Rails.cache" do
    # The test env defaults to :null_store. Swap in a real memory store
    # for the duration of this example so fetch's block only runs on
    # the first call.
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    described_class.pull_all(warehouse_id: warehouse_id)
    described_class.pull_all(warehouse_id: warehouse_id)

    expect(WebMock).to have_requested(:get, "https://www.flaschenpost.de/p/mio/mio-mio-mate-zero").once
  ensure
    Rails.cache = original_cache
  end
end
