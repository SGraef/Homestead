# frozen_string_literal: true
# typed: ignore

class AddFrozenOnToStorageItems < ActiveRecord::Migration[8.0]
  def change
    add_column :storage_items, :frozen_on, :date
    add_index  :storage_items, :frozen_on
  end
end
