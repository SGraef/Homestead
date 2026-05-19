# frozen_string_literal: true

# Per-household blocklist of patterns we never want to see in the offers
# feed (cat food when you don't have a cat, alcohol when you don't drink,
# pollen-season allergy ads, …). Patterns match offers' titles (the
# product name from Marktguru) case-insensitively as substrings -- one
# pattern per row so the management UI can list & remove them
# individually.
class CreateOfferBlocklistEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :offer_blocklist_entries do |t|
      t.references :household, null: false,
                   foreign_key: { on_delete: :cascade }
      t.string :pattern, null: false, limit: 200
      t.string :reason,  limit: 200
      t.timestamps
    end

    # Same pattern twice in one household is a no-op -- enforced.
    add_index :offer_blocklist_entries,
              %i[household_id pattern],
              unique: true,
              name: "idx_offer_blocklist_household_pattern"
  end
end
