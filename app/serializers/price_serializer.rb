# frozen_string_literal: true
# typed: true

class PriceSerializer
  # @param price [Price]
  # @return [Hash]
  def self.call(price)
    {
      id:           price.id,
      product_id:   price.product_id,
      store_id:     price.store_id,
      store_name:   price.store&.name,
      amount_cents: price.amount_cents,
      currency:     price.currency,
      observed_on:  price.observed_on,
      source:       price.source
    }
  end
end
