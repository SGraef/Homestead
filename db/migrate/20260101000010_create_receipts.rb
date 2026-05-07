# frozen_string_literal: true
# typed: ignore

class CreateReceipts < ActiveRecord::Migration[8.0]
  def change
    create_table :receipts do |t|
      t.references :household, null: false, foreign_key: true
      t.references :store,     foreign_key: true
      t.references :user,      foreign_key: true
      t.string  :status,              null: false, default: "pending"
      t.string  :detected_store_name
      t.text    :raw_text,            limit: 16_777_215 # MEDIUMTEXT
      t.string  :error_message,       limit: 1000
      t.date    :purchased_on
      t.bigint  :subtotal_cents
      t.string  :currency,            limit: 3, default: "EUR"
      t.datetime :parsed_at
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :receipts, %i[household_id status]
  end
end
