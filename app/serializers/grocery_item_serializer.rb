# frozen_string_literal: true
# typed: true

class GroceryItemSerializer
  # @param item [GroceryItem]
  # @return [Hash]
  def self.call(item)
    {
      id:                item.id,
      product_id:        item.product_id,
      product_name:      item.product&.name,
      product_barcode:   item.product&.barcode,
      store_id:          item.store_id,
      store_name:        item.store&.name,
      quantity:          item.quantity,
      status:            item.status,
      purchased_at:      item.purchased_at,
      paid_amount_cents: item.paid_amount_cents,
      paid_currency:     item.paid_currency
    }
  end
end
