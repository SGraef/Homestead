# frozen_string_literal: true

# Per-household watchlist: items the user is *always* interested in
# (coffee, oat milk, dishwasher tabs, …). Matched offers are sorted to
# the top of the /offers page and visually highlighted. This is distinct
# from the {GroceryItem} list -- that's a "buy this on the next trip"
# list; the watchlist is "tell me whenever this is on sale, even if I
# don't need it right now".
class CreateOfferWatchlistEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :offer_watchlist_entries do |t|
      t.references :household, null: false,
                   foreign_key: { on_delete: :cascade }
      t.string :pattern, null: false, limit: 200
      t.timestamps
    end

    # Same pattern twice in one household is a no-op.
    add_index :offer_watchlist_entries, %i[household_id pattern],
              unique: true,
              name: "idx_offer_watchlist_household_pattern"
  end
end
