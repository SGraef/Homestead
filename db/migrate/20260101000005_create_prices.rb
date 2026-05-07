# frozen_string_literal: true
# typed: ignore

class CreatePrices < ActiveRecord::Migration[8.0]
  def change
    create_table :prices do |t|
      t.references :product, null: false, foreign_key: true
      t.references :store,   null: false, foreign_key: true
      t.decimal :amount_cents, precision: 12, scale: 0, null: false
      t.string  :currency, null: false, default: "EUR", limit: 3
      t.date    :observed_on, null: false
      t.string  :source, default: "manual" # manual / receipt / scan
      t.timestamps
    end
    add_index :prices, %i[product_id store_id observed_on],
              name: "idx_prices_product_store_date"
  end
end
