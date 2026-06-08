# frozen_string_literal: true
# typed: false

class CreateProductSynonyms < ActiveRecord::Migration[8.0]
  def change
    create_table :product_synonyms do |t|
      t.references :product, null: false, foreign_key: true
      # Verbatim term as the user / receipt parser saw it ("MILCH 1L
      # ALDI"). Kept around so an admin reviewing synonyms can see the
      # raw spelling, not just the normalised form.
      t.string :term, null: false, limit: 200
      # Lowercased + whitespace-collapsed + non-alphanumeric stripped.
      # All lookups go through this column so "milch 1l", "Milch 1L"
      # and "MILCH-1L" all hit the same row.
      t.string :normalized_term, null: false, limit: 200
      t.timestamps
    end

    # Lookup index for the matcher. Not unique on its own -- two
    # different products in different households can legitimately
    # share a synonym ("Milch" → my Bio-Milch vs your neighbour's
    # Vollmilch).
    add_index :product_synonyms, :normalized_term

    # But per product, a given normalised term is unique -- there's no
    # point storing the same synonym twice for one product.
    add_index :product_synonyms, %i[product_id normalized_term], unique: true
  end
end
