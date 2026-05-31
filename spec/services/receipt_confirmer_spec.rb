# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ReceiptConfirmer do
  let(:user)      { create(:user) }
  let(:household) { create(:household, admin: user) }
  let(:receipt) do
    r = Receipt.new(
      household: household, user: user,
      detected_store_name: "REWE Mitte",
      purchased_on: Date.new(2026, 5, 1),
      currency: "EUR",
      status: "parsed"
    )
    r.save!(validate: false) # confirmer doesn't care about image attachment
    r
  end

  let(:milk_line) do
    receipt.receipt_line_items.create!(
      position: 1, line_text: "Vollmilch 1L 1,19 A",
      parsed_name: "Vollmilch 1L", parsed_total_cents: 119, parsed_quantity: 1
    )
  end

  let(:eggs_line) do
    receipt.receipt_line_items.create!(
      position: 2, line_text: "Bio Eier 6er 2,99 A",
      parsed_name: "Bio Eier 6er", parsed_total_cents: 299, parsed_quantity: 1
    )
  end

  it "creates a new store and products with prices, and marks the receipt confirmed" do
    milk_line
    eggs_line

    params = {
      new_store_name: "REWE Mitte",
      lines:          {
        milk_line.id.to_s => { action: "create", name: "Whole Milk 1L", unit: "l", barcode: "4006381333924" },
        eggs_line.id.to_s => { action: "create", name: "Bio Eggs 6", unit: "pcs" }
      }
    }

    expect do
      described_class.new(receipt: receipt, user: user, params: params).call
    end.to change(Store, :count).by(1)
                                .and change(Product, :count).by(2)
                                                            .and change(Price, :count).by(2)

    receipt.reload
    expect(receipt.status).to eq("confirmed")
    expect(receipt.store.name).to eq("REWE Mitte")
    expect(milk_line.reload).to have_attributes(status: "created")
    expect(milk_line.product.barcode).to eq("4006381333924")
  end

  it "reuses an existing store when store_id is given" do
    store = create(:store, household: household, name: "REWE Existing")
    milk_line

    params = {
      store_id: store.id,
      lines:    { milk_line.id.to_s => { action: "create", name: "Milk", unit: "l" } }
    }

    expect do
      described_class.new(receipt: receipt, user: user, params: params).call
    end.not_to change(Store, :count)

    expect(receipt.reload.store).to eq(store)
  end

  it "skips lines marked as skip" do
    milk_line
    params = {
      new_store_name: "REWE",
      lines:          { milk_line.id.to_s => { action: "skip" } }
    }
    expect do
      described_class.new(receipt: receipt, user: user, params: params).call
    end.not_to change(Product, :count)
    expect(milk_line.reload.status).to eq("ignored")
  end

  describe "stocking the storage on confirm" do
    it "creates a StorageItem per matched/created line at the per-line location" do
      milk_line
      eggs_line

      params = {
        new_store_name: "REWE Mitte",
        lines:          {
          milk_line.id.to_s => { action: "create", name: "Milk", unit: "l",
                                  to_storage: "1",
                                  location: "fridge", expires_on: "2026-05-13" },
          eggs_line.id.to_s => { action: "create", name: "Eggs", unit: "pcs",
                                  to_storage: "1",
                                  location: "pantry" }
        }
      }

      expect do
        described_class.new(receipt: receipt, user: user, params: params).call
      end.to change(StorageItem, :count).by(2)

      milk_storage = StorageItem.joins(:product).find_by(products: { name: "Milk" })
      eggs_storage = StorageItem.joins(:product).find_by(products: { name: "Eggs" })

      expect(milk_storage).to have_attributes(
        quantity:   milk_line.parsed_quantity,
        expires_on: Date.new(2026, 5, 13)
      )
      expect(milk_storage.location.kind).to eq("fridge")
      expect(eggs_storage).to have_attributes(expires_on: nil)
      expect(eggs_storage.location.kind).to eq("pantry")
    end

    it "skips storage for lines whose to_storage box is unchecked" do
      milk_line
      eggs_line

      params = {
        new_store_name: "REWE",
        lines:          {
          # to_storage "0" mirrors what the unchecked-checkbox + hidden
          # sibling submit -- bought, but not stocked.
          milk_line.id.to_s => { action: "create", name: "Milk", unit: "l",
                                  to_storage: "0", location: "pantry" },
          eggs_line.id.to_s => { action: "create", name: "Eggs", unit: "pcs",
                                  to_storage: "1", location: "pantry" }
        }
      }

      expect do
        described_class.new(receipt: receipt, user: user, params: params).call
      end.to change(StorageItem, :count).by(1)

      expect(StorageItem.joins(:product).where(products: { name: "Milk" })).to be_empty
    end

    it "does not stock when the to_storage param is missing" do
      milk_line

      params = {
        new_store_name: "REWE",
        lines:          { milk_line.id.to_s => { action: "create", name: "Milk", unit: "l" } }
      }

      expect do
        described_class.new(receipt: receipt, user: user, params: params).call
      end.not_to change(StorageItem, :count)
    end

    it "skips storage for lines whose action is 'skip'" do
      milk_line

      params = {
        new_store_name: "REWE",
        lines:          { milk_line.id.to_s => { action: "skip", to_storage: "1" } }
      }

      expect do
        described_class.new(receipt: receipt, user: user, params: params).call
      end.not_to change(StorageItem, :count)
    end

    it "falls back to 'pantry' when the per-line location is invalid or missing" do
      milk_line

      params = {
        new_store_name: "REWE",
        lines:          {
          milk_line.id.to_s => { action: "create", name: "Milk", unit: "l",
                                  to_storage: "1",
                                  location: "garage" } # not in StorageItem::LOCATIONS
        }
      }

      described_class.new(receipt: receipt, user: user, params: params).call

      expect(StorageItem.last.location.kind).to eq("pantry")
    end
  end

  describe "per-piece pricing" do
    it "divides the line total by pieces and stores the per-piece amount" do
      apples = receipt.receipt_line_items.create!(
        position: 1, line_text: "3 x Apfel 3,99",
        parsed_name: "Apfel", parsed_total_cents: 399, parsed_quantity: 1
      )

      params = {
        new_store_name: "REWE",
        lines:          {
          apples.id.to_s => { action: "create", name: "Apple", unit: "pcs",
                              pieces: "3", to_storage: "1", location: "fridge" }
        }
      }

      described_class.new(receipt: receipt, user: user, params: params).call

      product = Product.find_by(name: "Apple")
      price   = Price.find_by(product: product)
      storage = StorageItem.find_by(product: product)

      expect(price.amount_cents).to eq(133)            # 399 / 3, rounded
      expect(storage.quantity).to eq(3)
    end

    it "accepts decimal pieces (e.g. 0.65 kg) and stores the divided price" do
      bananas = receipt.receipt_line_items.create!(
        position: 1, line_text: "0,650 kg Bananen 1,29",
        parsed_name: "Bananen", parsed_total_cents: 129, parsed_quantity: 1
      )

      params = {
        new_store_name: "REWE",
        lines:          {
          bananas.id.to_s => { action: "create", name: "Bananas", unit: "kg",
                               pieces: "0,650", to_storage: "1", location: "pantry" }
        }
      }

      described_class.new(receipt: receipt, user: user, params: params).call

      product = Product.find_by(name: "Bananas")
      price   = Price.find_by(product: product)
      storage = StorageItem.find_by(product: product)
      # 129 / 0.65 ≈ 198.46… → 198 cents per kg
      expect(price.amount_cents).to eq(198)
      expect(storage.quantity).to eq(BigDecimal("0.65"))
    end

    it "falls back to 1 piece (full total) when the pieces field is blank or junk" do
      milk_line
      params = {
        new_store_name: "REWE",
        lines:          {
          milk_line.id.to_s => { action: "create", name: "Milk", unit: "l", pieces: "" }
        }
      }
      described_class.new(receipt: receipt, user: user, params: params).call
      expect(Price.last.amount_cents).to eq(milk_line.parsed_total_cents)
    end
  end

  describe "shopping-list cleanup on confirm" do
    it "marks any 'needed' grocery items for the matched product as purchased" do
      product = create(:product, household: household, name: "Vollmilch")
      gi      = create(:grocery_item, household: household, product: product, status: "needed")

      milk_line.update!(parsed_name: "Vollmilch")

      params = {
        new_store_name: "REWE",
        lines:          {
          milk_line.id.to_s => { action: "match", product_id: product.id, pieces: "1" }
        }
      }

      described_class.new(receipt: receipt, user: user, params: params).call

      expect(gi.reload).to have_attributes(status: "purchased")
      expect(gi.purchased_at).to be_within(2.seconds).of(Time.current)
    end

    it "does not double-create a StorageItem when the grocery item also flips" do
      product = create(:product, household: household, name: "Brot")
      create(:grocery_item, household: household, product: product, status: "needed")

      bread_line = receipt.receipt_line_items.create!(
        position: 1, line_text: "Brot 2,49",
        parsed_name: "Brot", parsed_total_cents: 249, parsed_quantity: 1
      )

      params = {
        new_store_name: "REWE",
        lines:          {
          bread_line.id.to_s => { action: "match", product_id: product.id,
                                  pieces: "1", to_storage: "1", location: "pantry" }
        }
      }

      # exactly one — not two
      expect do
        described_class.new(receipt: receipt, user: user, params: params).call
      end.to change(StorageItem, :count).by(1)
    end

    it "leaves grocery items for unrelated products alone" do
      other     = create(:product, household: household, name: "Eier")
      other_gi  = create(:grocery_item, household: household, product: other, status: "needed")

      milk_line
      params = {
        new_store_name: "REWE",
        lines:          { milk_line.id.to_s => { action: "create", name: "Milk", unit: "l" } }
      }

      described_class.new(receipt: receipt, user: user, params: params).call
      expect(other_gi.reload.status).to eq("needed")
    end
  end
end
