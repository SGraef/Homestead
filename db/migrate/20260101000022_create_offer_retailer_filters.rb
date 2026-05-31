# frozen_string_literal: true

# Per-household allow-list of retailers. When the household has at least
# one entry, the offer sync only writes offers whose retailer (name OR
# Marktguru slug, case-insensitive) is in the list. Empty list = no
# filtering (current default of "all retailers in the configured
# industries").
class CreateOfferRetailerFilters < ActiveRecord::Migration[8.0]
  def change
    create_table :offer_retailer_filters do |t|
      t.references :household, null:        false,
                               foreign_key: { on_delete: :cascade }
      t.string :retailer, null: false, limit: 80
      t.timestamps
    end

    add_index :offer_retailer_filters, %i[household_id retailer],
              unique: true, name: "idx_offer_retailer_filter_household_retailer"
  end
end
