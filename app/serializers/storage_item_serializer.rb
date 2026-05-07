# frozen_string_literal: true
# typed: true

class StorageItemSerializer
  # @param item [StorageItem]
  # @return [Hash]
  def self.call(item)
    {
      id:                item.id,
      product_id:        item.product_id,
      product_name:      item.product&.name,
      product_barcode:   item.product&.barcode,
      quantity:          item.quantity,
      location_id:       item.location_id,
      location_name:     item.location&.name,
      location_kind:     item.location&.kind,
      expires_on:        item.expires_on,
      opened_on:         item.opened_on,
      frozen_on:         item.frozen_on,
      days_until_expiry: item.days_until_expiry,
      days_in_freezer:   item.days_in_freezer
    }
  end
end
