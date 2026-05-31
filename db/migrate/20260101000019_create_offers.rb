# frozen_string_literal: true

# Persistent record of a promotional offer pulled from a third-party flyer
# aggregator (initially Marktguru). Distinct from {Price} because:
#
#   * It's time-bounded (valid_from / valid_until).
#   * The `product_id` and `store_id` may be NULL: the offer can name an
#     SKU we don't yet stock and a retailer we don't yet have a Store row
#     for. We still want to display it -- the link can be backfilled later.
#   * The price is per *promotional unit*, not normalized — we keep the
#     human-readable amount (`quantity_text`) alongside.
class CreateOffers < ActiveRecord::Migration[8.0]
  def change
    create_table :offers do |t|
      t.references :household, null:        false,
                               foreign_key: { on_delete: :cascade }
      t.references :product,   null:        true,
                               foreign_key: { on_delete: :nullify }
      t.references :store,     null:        true,
                               foreign_key: { on_delete: :nullify }

      t.string  :source,         null: false, default: "marktguru", limit: 32
      t.string  :external_id,    null: false, limit: 64
      t.string  :retailer_name,  null: false, limit: 80
      t.string  :title,          null: false, limit: 200
      t.string  :brand,          limit: 80
      t.string  :category,       limit: 80
      t.integer :price_cents,    null: false
      t.integer :regular_price_cents
      t.string  :currency,       null: false, default: "EUR", limit: 8
      t.string  :unit,           limit: 16
      t.string  :quantity_text,  limit: 80
      t.text    :image_url
      t.text    :source_url
      t.date    :valid_from
      t.date    :valid_until

      t.timestamps
    end

    # Listing current offers for a household ("WHERE valid_until >= today").
    add_index :offers, %i[household_id valid_until]
    # "What's on offer for this product I already track?"
    add_index :offers, %i[household_id product_id]
    # Upsert dedup key: same household + same source + same upstream id.
    add_index :offers, %i[household_id source external_id], unique: true
  end
end
