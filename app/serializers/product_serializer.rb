# frozen_string_literal: true
# typed: true

# Lightweight POROs for the JSON API; we deliberately avoid jsonapi-serializer
# DSL here so Sorbet can fully type the shapes returned to clients.
class ProductSerializer
  # @param product [Product]
  # @param include_prices [Boolean]
  # @return [Hash]
  def self.call(product, include_prices: false)
    payload = {
      id:           product.id,
      name:         product.name,
      brand:        product.brand,
      barcode:      product.barcode,
      barcodes:     product.product_barcodes.map do |pb|
        { id: pb.id, barcode: pb.barcode, brand: pb.brand,
          quantity_text: pb.quantity_text }
      end,
      all_barcodes: product.all_barcodes,
      all_brands:   product.all_brands,
      unit:         product.unit,
      category:     product.category,
      notes:        product.notes,
      created_at:   product.created_at,
      updated_at:   product.updated_at
    }
    payload[:prices] = product.prices.includes(:store).recent.map { |p| PriceSerializer.call(p) } if include_prices
    payload
  end
end
