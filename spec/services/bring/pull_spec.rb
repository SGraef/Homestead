# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Bring::Pull do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:connection) do
    BringConnection.create!(
      household:               household,
      bring_email:             "demo@example.com",
      bring_user_uuid:         "u-1",
      default_list_uuid:       "l-1",
      access_token:            "tok",
      refresh_token:           "r",
      access_token_expires_at: 1.hour.from_now,
      country_code:            "DE"
    )
  end

  def stub_list(purchase: [], recently: [])
    stub_request(:get, "https://api.getbring.com/rest/v2/bringlists/l-1")
      .to_return(
        status:  200,
        headers: { "Content-Type" => "application/json" },
        body:    {
          uuid: "l-1", status: "REGISTERED",
          purchase: purchase.map { |n| { name: n, specification: "" } },
          recently: recently.map { |n| { name: n, specification: "" } }
        }.to_json
      )
  end

  it "creates a free-form GroceryItem (no Product) for each Bring item that's new locally" do
    stub_list(purchase: %w[Vollmilch Brot])

    expect do
      outcome = described_class.new(connection).call
      expect(outcome.added).to eq(2)
    end.not_to change(Product, :count)

    rows = household.grocery_items.needed.order(:name)
    expect(rows.pluck(:name)).to match_array(%w[Brot Vollmilch])
    expect(rows.pluck(:product_id).compact).to be_empty
  end

  it "links to an existing product (incl. via a synonym) instead of creating a freeform row" do
    milch = create(:product, household: household, name: "Milch")
    milch.product_synonyms.create!(term: "Vollmilch")
    stub_list(purchase: %w[Vollmilch])

    expect do
      described_class.new(connection).call
    end.not_to change(Product, :count)

    gi = household.grocery_items.needed.first
    expect(gi.product).to eq(milch)
    expect(gi.name).to be_blank
  end

  it "is idempotent: a second pull with the same Bring state changes nothing" do
    stub_list(purchase: ["Vollmilch"])

    described_class.new(connection).call
    outcome = described_class.new(connection).call

    expect(outcome.added).to eq(0)
    expect(outcome.reactivated).to eq(0)
    expect(household.grocery_items.count).to eq(1)
  end

  it "reactivates a previously purchased item when Bring puts it back on the list" do
    product = create(:product, household: household, name: "Vollmilch")
    gi      = create(:grocery_item, household: household, product: product, status: "purchased")
    stub_list(purchase: ["Vollmilch"])

    outcome = described_class.new(connection).call

    expect(outcome.reactivated).to eq(1)
    expect(gi.reload.status).to eq("needed")
  end

  it "marks a needed item as purchased when Bring shows it as recently bought" do
    product = create(:product, household: household, name: "Brot")
    gi      = create(:grocery_item, household: household, product: product, status: "needed")
    stub_list(recently: ["Brot"])

    outcome = described_class.new(connection).call

    expect(outcome.marked_purchased).to eq(1)
    expect(gi.reload.status).to eq("purchased")
  end

  it "does not echo pull-time writes back to Bring (no push job enqueued)" do
    stub_list(purchase: ["Vollmilch"])

    expect do
      described_class.new(connection).call
    end.not_to have_enqueued_job(SyncGroceryToBringJob)
  end

  it "stamps last_synced_at on success" do
    stub_list(purchase: [])
    described_class.new(connection).call
    expect(connection.reload.last_synced_at).to be_within(2.seconds).of(Time.current)
  end

  # The M0-decided Bring! conflict policy: UNION (keep every item present in
  # either system), Bring! WINS TIES (its needed/bought state overrides local),
  # and ABSENCE != DELETE (an item missing from Bring's list is "not yet
  # synced", never silently removed). These exercise the sharp edges of that
  # policy that the per-feature specs above don't isolate.
  describe "M0 conflict policy (union / Bring-wins / no silent delete)" do
    it "never deletes a local item that Bring's list omits (absence = not-yet-synced)" do
      keep = create(:grocery_item, household: household, product: nil, name: "Hafermilch", status: "needed")
      stub_list(purchase: ["Vollmilch"]) # Bring has no idea about Hafermilch

      described_class.new(connection).call

      expect(keep.reload.status).to eq("needed")
      expect(household.grocery_items.where(product_id: nil).pluck(:name)).to include("Hafermilch", "Vollmilch")
    end

    it "de-duplicates a name Bring repeats (incl. case variants) into a single row" do
      stub_list(purchase: %w[Vollmilch Vollmilch vollmilch])

      outcome = described_class.new(connection).call

      expect(outcome.added).to eq(1) # first creates; the repeats locate it (LOWER(name))
      expect(household.grocery_items.count).to eq(1)
    end

    it "resolves an item Bring lists as BOTH active and recently-bought to purchased" do
      stub_list(purchase: ["Brot"], recently: ["Brot"])

      described_class.new(connection).call

      gi = household.grocery_items.find_by("LOWER(name) = ?", "brot")
      expect(gi.status).to eq("purchased") # active creates needed, then recently flips it
    end

    it "reactivates a free-form (productless) row Bring re-lists instead of duplicating it" do
      gi = create(:grocery_item, household: household, product: nil, name: "Hafermilch", status: "purchased")
      stub_list(purchase: ["Hafermilch"])

      outcome = described_class.new(connection).call

      expect(outcome.reactivated).to eq(1)
      expect(household.grocery_items.count).to eq(1)
      expect(gi.reload.status).to eq("needed")
    end

    it "applies union + Bring-wins across a mixed list while deleting nothing" do
      apfel = create(:grocery_item, household: household, product: nil, name: "Apfel", status: "needed")
      brot  = create(:grocery_item, household: household, product: nil, name: "Brot",  status: "purchased")
      milch = create(:grocery_item, household: household, product: nil, name: "Milch", status: "needed")
      stub_list(purchase: %w[Brot Eier], recently: ["Milch"])

      described_class.new(connection).call

      expect(apfel.reload.status).to eq("needed")    # local-only -> untouched
      expect(brot.reload.status).to eq("needed")     # Bring active -> reactivated
      expect(milch.reload.status).to eq("purchased") # Bring recently -> purchased
      expect(household.grocery_items.where("LOWER(name) = ?", "eier")).to exist # union: new from Bring
      expect(household.grocery_items.count).to eq(4) # nothing deleted
    end
  end
end
