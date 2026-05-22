# frozen_string_literal: true

# Until now Price#amount_per_normalized_unit assumed every product's
# listed price was for exactly "1 of its unit" (1 kg, 1 L, 1 piece).
# That's wrong as soon as you have a 500 g pack or a 6-pack of beer:
# the derived per-kg / per-l number was either misleading or just
# the same as the total.
#
# Add pack_quantity so a price can record "this is the cost of N of
# the product's unit". The per-normalized-unit math then divides by
# the pack quantity. Default 1 keeps existing rows behaving as
# before until they're edited.
class AddPackQuantityToPrices < ActiveRecord::Migration[8.0]
  def change
    add_column :prices, :pack_quantity, :decimal,
               precision: 12, scale: 4, null: false, default: 1
  end
end
