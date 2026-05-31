# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ExpenseReport do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:store)     { create(:store, household: household) }

  def build_confirmed_receipt(date:, total_cents:, lines: [])
    r = Receipt.new(
      household:      household,
      user:           user,
      store:          store,
      status:         "confirmed",
      confirmed_at:   Time.current,
      purchased_on:   date,
      subtotal_cents: total_cents,
      currency:       "EUR"
    )
    r.save!(validate: false)

    lines.each do |attrs|
      # `no_product: true` simulates skipped / OCR-only lines that the
      # receipt confirmer never attached to a Product.
      product =
        if attrs[:no_product]
          nil
        else
          household.products.create!(
            name:     attrs[:name],
            unit:     attrs[:unit] || "pcs",
            category: attrs[:category]
          )
        end
      r.receipt_line_items.create!(
        position:           attrs[:position] || 1,
        line_text:          attrs[:name],
        parsed_name:        attrs[:name],
        parsed_total_cents: attrs[:cents],
        parsed_quantity:    attrs[:quantity] || 1,
        product:            product,
        status:             attrs[:status] || "matched"
      )
    end
    r
  end

  describe "#months" do
    it "aggregates totals per month and groups line items by category" do
      build_confirmed_receipt(
        date:        Date.new(2026, 5, 3),
        total_cents: 1500,
        lines:       [
          { name: "Milk",  category: "dairy", cents: 800 },
          { name: "Bread", category: "bakery", cents: 600 }
        ]
      )
      build_confirmed_receipt(
        date:        Date.new(2026, 5, 20),
        total_cents: 500,
        lines:       [{ name: "Cheese", category: "dairy", cents: 500 }]
      )
      build_confirmed_receipt(
        date:        Date.new(2026, 4, 15),
        total_cents: 700,
        lines:       [{ name: "Apples", category: "produce", cents: 700 }]
      )

      report = described_class.new(household: household, months: 6)
      months = report.months

      may = months.find { |m| m.key == "2026-05" }
      apr = months.find { |m| m.key == "2026-04" }

      expect(may.total_cents).to eq(2000)
      expect(may.by_category).to eq("dairy" => 1300, "bakery" => 600)
      expect(may.uncategorized_cents).to eq(100) # 2000 - (800 + 600 + 500)

      expect(apr.total_cents).to eq(700)
      expect(apr.by_category).to eq("produce" => 700)
      expect(apr.uncategorized_cents).to eq(0)
    end

    it "buckets line items with NULL or empty category as 'uncategorized'" do
      build_confirmed_receipt(
        date:        Date.current,
        total_cents: 400,
        lines:       [
          { name: "Bag of Stuff", category: nil, cents: 250 },
          { name: "Mystery",      category: "",  cents: 150 }
        ]
      )

      month = described_class.new(household: household, months: 1).current_month
      expect(month.by_category[ExpenseReport::UNCATEGORIZED]).to eq(400)
    end

    it "ignores skipped/ignored line items in the category breakdown" do
      build_confirmed_receipt(
        date:        Date.current,
        total_cents: 1000,
        lines:       [
          { name: "Counted",  category: "x", cents: 700, status: "matched" },
          { name: "Ignored",  category: "x", cents: 300, status: "ignored" }
        ]
      )

      month = described_class.new(household: household, months: 1).current_month
      expect(month.by_category["x"]).to eq(700)
      expect(month.uncategorized_cents).to eq(300)
    end

    it "rolls non-product line items into the 'other' bucket" do
      build_confirmed_receipt(
        date:        Date.current,
        total_cents: 1500,
        lines:       [
          { name: "Milk", category: "dairy", cents: 800, status: "matched" },
          # User skipped these: confirmer leaves product nil and status 'ignored'.
          { name: "Pfand",                       cents: 250, status: "ignored",
            no_product: true },
          { name: "Coupon noise",                cents: 450, status: "ignored",
            no_product: true }
        ]
      )

      month = described_class.new(household: household, months: 1).current_month
      expect(month.by_category["dairy"]).to eq(800)
      expect(month.by_category[ExpenseReport::OTHER]).to eq(700)  # 250 + 450
      expect(month.uncategorized_cents).to eq(0)                  # 1500 fully accounted
    end

    it "leaves 'other' out of by_category when no non-product lines exist" do
      build_confirmed_receipt(
        date:        Date.current,
        total_cents: 800,
        lines:       [{ name: "Milk", category: "dairy", cents: 800 }]
      )

      month = described_class.new(household: household, months: 1).current_month
      expect(month.by_category).not_to have_key(ExpenseReport::OTHER)
    end
  end

  describe "#current_month" do
    it "returns a zero month when nothing was bought yet" do
      month = described_class.new(household: household).current_month
      expect(month.total_cents).to eq(0)
      expect(month.by_category).to be_empty
    end
  end
end
