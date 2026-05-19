# frozen_string_literal: true

# Per-household offer category rules. Replaces the static
# `config/offer_categories.yml` mapping with editable records so
# households can rename buckets, reorder priorities (which determine
# tie-breaks in classification) and curate keywords from the web UI.
class CreateOfferCategoriesAndKeywords < ActiveRecord::Migration[8.0]
  def change
    create_table :offer_categories do |t|
      t.references :household, null: false,
                   foreign_key: { on_delete: :cascade }
      t.string  :name,     null: false, limit: 80
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # Position drives match order (brand-rich categories first beats
    # generic-ingredient ones); names are unique per household so the
    # classification step can't collide on identical labels.
    add_index :offer_categories, %i[household_id position],
              name: "idx_offer_categories_household_position"
    add_index :offer_categories, %i[household_id name],
              unique: true,
              name: "idx_offer_categories_household_name"

    create_table :offer_category_keywords do |t|
      t.references :offer_category, null: false,
                   foreign_key: { on_delete: :cascade }
      t.string :keyword, null: false, limit: 80
      t.timestamps
    end

    add_index :offer_category_keywords, %i[offer_category_id keyword],
              unique: true,
              name: "idx_offer_category_keywords_cat_keyword"
  end
end
