# frozen_string_literal: true

# Per-household warehouse_id for the Flaschenpost offer source. Their
# product API is region-locked behind an integer warehouse picked from
# the user's delivery ZIP, and the mapping isn't cleanly exposed via
# their public endpoints -- so each household sets it once after
# finding the right value in their browser's devtools.
#
# Nullable: a household with no value just skips Flaschenpost during
# the daily sync.
class AddFlaschenpostWarehouseIdToHouseholds < ActiveRecord::Migration[8.0]
  def change
    add_column :households, :flaschenpost_warehouse_id, :integer
  end
end
