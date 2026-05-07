# frozen_string_literal: true
# typed: ignore

class CreateReceiptLineItems < ActiveRecord::Migration[8.0]
  def change
    create_table :receipt_line_items do |t|
      t.references :receipt, null: false, foreign_key: true
      t.references :product, foreign_key: true
      t.integer    :position
      t.string     :line_text,    limit: 1000
      t.string     :parsed_name,  limit: 200
      t.decimal    :parsed_quantity, precision: 12, scale: 3, default: 1
      t.bigint     :parsed_unit_price_cents
      t.bigint     :parsed_total_cents
      t.string     :status, null: false, default: "unmatched"
      t.timestamps
    end
    add_index :receipt_line_items, %i[receipt_id position]
  end
end
