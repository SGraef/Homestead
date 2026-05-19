# frozen_string_literal: true

# Postal code drives Marktguru's localization -- offers are scoped per
# postcode in their flyer index. Optional: households without one simply
# skip the offer sync.
class AddPostalCodeToHouseholds < ActiveRecord::Migration[8.0]
  def change
    add_column :households, :postal_code, :string, limit: 16
  end
end
