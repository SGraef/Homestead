# frozen_string_literal: true
# typed: true

class StoreSerializer
  # @param store [Store]
  # @return [Hash]
  def self.call(store)
    {
      id:      store.id,
      name:    store.name,
      chain:   store.chain,
      address: store.address,
      url:     store.url
    }
  end
end
