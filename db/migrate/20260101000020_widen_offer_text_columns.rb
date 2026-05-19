# frozen_string_literal: true

# Marktguru's `description` field can be a full marketing sentence
# ("oder Die Streichzarte versch. Sorten, je 250-g-Pckg./ Becher",
# sometimes much longer). The original 80-char limit on quantity_text
# was sized for hand-entered free text -- aggregator data needs more
# room. Title also occasionally runs past 200 chars on long SKU names.
class WidenOfferTextColumns < ActiveRecord::Migration[8.0]
  def up
    change_column :offers, :quantity_text, :text
    change_column :offers, :title,         :string, limit: 500
  end

  def down
    change_column :offers, :quantity_text, :string, limit: 80
    change_column :offers, :title,         :string, limit: 200
  end
end
