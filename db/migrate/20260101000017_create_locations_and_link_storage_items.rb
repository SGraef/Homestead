# frozen_string_literal: true
# typed: ignore

# Promote storage locations from a hard-coded string column on StorageItem
# to a first-class `locations` table per household, so the user can rename
# them ("Garage Tiefkühltruhe"), add new ones ("Schrank links"), and
# track different quantities of the same product across multiple places.
#
# Migration steps:
#   1. Create `locations`.
#   2. Seed every existing household with one location per known kind.
#   3. Add `location_id` to `storage_items` and backfill from the old
#      string column (matching by `kind`, falling back to "other").
#   4. Make `location_id` non-null and drop the old string column.
class CreateLocationsAndLinkStorageItems < ActiveRecord::Migration[8.0]
  KINDS = %w[pantry fridge freezer cellar other].freeze

  def up
    create_table :locations do |t|
      t.references :household, null: false, foreign_key: true
      t.string  :name,     null: false
      t.string  :kind,     null: false, default: "other"
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :locations, %i[household_id name], unique: true
    add_index :locations, %i[household_id kind]

    say_with_time "Seeding default locations per household" do
      Household.find_each do |h|
        KINDS.each_with_index do |kind, i|
          h.locations.find_or_create_by!(name: kind) do |loc|
            loc.kind     = kind
            loc.position = i
          end
        end
      end
    end

    add_reference :storage_items, :location, foreign_key: { to_table: :locations }

    say_with_time "Linking storage_items.location_id" do
      StorageItem.reset_column_information
      StorageItem.find_each do |si|
        kind = si["location"].presence_in(KINDS) || "other"
        loc  = si.household.locations.find_by(kind: kind) ||
               si.household.locations.find_by(kind: "other")
        si.update_column(:location_id, loc.id)
      end
    end

    change_column_null :storage_items, :location_id, false
    remove_index :storage_items, name: "index_storage_items_on_household_id_and_product_id_and_location" if index_exists?(:storage_items, %i[household_id product_id location], name: "index_storage_items_on_household_id_and_product_id_and_location")
    remove_column :storage_items, :location, :string
  end

  def down
    add_column :storage_items, :location, :string
    StorageItem.reset_column_information
    StorageItem.find_each do |si|
      kind = si.location&.kind || "other"
      si.update_column(:location, kind)
    end
    remove_reference :storage_items, :location, foreign_key: true
    drop_table :locations
  end
end
