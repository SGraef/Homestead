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
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          uuid: "l-1", status: "REGISTERED",
          purchase: purchase.map { |n| { name: n, specification: "" } },
          recently: recently.map { |n| { name: n, specification: "" } }
        }.to_json
      )
  end

  it "creates a Product + needed GroceryItem for each Bring item that's new locally" do
    stub_list(purchase: ["Vollmilch", "Brot"])

    outcome = described_class.new(connection).call

    expect(outcome.added).to eq(2)
    expect(household.grocery_items.needed.count).to eq(2)
    expect(household.products.pluck(:name)).to match_array(%w[Vollmilch Brot])
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

    expect {
      described_class.new(connection).call
    }.not_to have_enqueued_job(SyncGroceryToBringJob)
  end

  it "stamps last_synced_at on success" do
    stub_list(purchase: [])
    described_class.new(connection).call
    expect(connection.reload.last_synced_at).to be_within(2.seconds).of(Time.current)
  end
end
