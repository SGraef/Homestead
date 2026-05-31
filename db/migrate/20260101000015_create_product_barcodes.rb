# frozen_string_literal: true
# typed: ignore

# Alternate barcodes (per-brand SKUs) for a single product. Lets a "Butter"
# product carry a Kerrygold EAN, an ALDI EAN, etc. — so any of them scans to
# the same product on the storage / grocery side.
class CreateProductBarcodes < ActiveRecord::Migration[8.0]
  def change
    create_table :product_barcodes do |t|
      t.references :product, null: false, foreign_key: true
      t.string  :barcode, null: false
      t.string  :brand
      t.string  :quantity_text # e.g., "250 g", "1 L"
      t.timestamps
    end
    # MySQL allows multiple NULLs in a unique index, so this is safe even if
    # someone briefly inserts a row without a barcode -- but the model
    # validates barcode presence anyway.
    add_index :product_barcodes, %i[product_id barcode], unique: true,
                                                         name:   :idx_product_barcodes_product_barcode
    add_index :product_barcodes, :barcode
  end
end
