# frozen_string_literal: true
# typed: true

# Pull half of the Bring! sync. Fetches the list state from Bring! and
# reconciles it into the household's grocery items.
#
# Reconciliation rules (Bring is the source of truth for the list):
#   purchase[]  → ensure a needed GroceryItem exists for that product (create
#                 the Product on the fly if missing, reactivate it if a
#                 purchased/cancelled row exists)
#   recently[]  → if a needed GroceryItem exists for that product, mark it
#                 purchased (mirroring the Bring "recently bought" state)
#
# All writes are wrapped in {GroceryItem.without_bring_sync} so the
# after-commit callbacks don't push back what we just pulled.
module Bring
  class Pull
    Outcome = Struct.new(:added, :reactivated, :marked_purchased, :unchanged,
                         keyword_init: true) do
      def total_changed = added + reactivated + marked_purchased
    end

    # @param connection [BringConnection]
    def initialize(connection)
      @connection = connection
      @household  = connection.household
    end

    # @return [Outcome]
    def call
      list = Bring::Client.new(@connection).fetch_list

      active = names(list["purchase"])
      recent = names(list["recently"])

      added = reactivated = marked_purchased = unchanged = 0

      GroceryItem.without_bring_sync do
        active.each do |name|
          case sync_active(name)
          when :added            then added += 1
          when :reactivated      then reactivated += 1
          when :unchanged        then unchanged += 1
          end
        end

        recent.each do |name|
          marked_purchased += 1 if sync_recent(name)
        end
      end

      @connection.update_columns(last_synced_at: Time.current,
                                 last_error:     nil,
                                 updated_at:     Time.current)

      Outcome.new(added: added, reactivated: reactivated,
                  marked_purchased: marked_purchased, unchanged: unchanged)
    end

    private

    # Bring's list payload uses { name, specification }; we only key on name.
    def names(items)
      Array(items).map { |i| i["name"].to_s.strip }.reject(&:empty?).uniq
    end

    # @return [:added, :reactivated, :unchanged]
    def sync_active(name)
      product = find_or_create_product(name)
      gi      = @household.grocery_items.find_by(product: product)

      if gi.nil?
        @household.grocery_items.create!(product: product, status: "needed", quantity: 1)
        :added
      elsif gi.status != "needed"
        gi.update!(status: "needed", purchased_at: nil)
        :reactivated
      else
        :unchanged
      end
    end

    # @return [Boolean] true if a row was flipped
    def sync_recent(name)
      product = @household.products.find_by(name: name)
      return false unless product

      gi = @household.grocery_items.find_by(product: product, status: "needed")
      return false unless gi

      gi.update!(status: "purchased", purchased_at: Time.current)
      true
    end

    def find_or_create_product(name)
      @household.products.find_or_create_by!(name: name) do |p|
        p.unit = "pcs"
      end
    end
  end
end
