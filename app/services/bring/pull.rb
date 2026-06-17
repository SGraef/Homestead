# frozen_string_literal: true
# typed: true

# Pull half of the Bring! sync. Fetches the list state from Bring! and
# reconciles it into the household's grocery items.
#
# Reconciliation rules (Bring is the source of truth for the list):
#   purchase[]  → ensure a needed GroceryItem exists for that name.
#                 We try to resolve the name against the household's
#                 product catalogue first (primary name OR registered
#                 synonym, via Product.match_by_term). On a hit the
#                 row links to that product so offer matching + auto-
#                 stock-on-purchase work. On a miss we create a
#                 free-form row -- no Product is materialised behind
#                 the user's back. Reactivates a purchased/cancelled
#                 row instead of duplicating.
#   recently[]  → if a needed GroceryItem matches (by product OR by
#                 free-form name), mark it purchased.
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
      Telemetry.in_span("bring.pull",
                        attributes: { "pantria.household.id" => @household.id }) do |span|
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
            marked_purchased += 1 if sync_recent?(name)
          end
        end

        @connection.update_columns(last_synced_at: Time.current,
                                   last_error:     nil,
                                   updated_at:     Time.current)

        outcome = Outcome.new(added: added, reactivated: reactivated,
                              marked_purchased: marked_purchased, unchanged: unchanged)
        record_pull_metrics(span, outcome)
        outcome
      end
    end

    private

    def record_pull_metrics(span, outcome)
      if span.respond_to?(:set_attribute)
        span.set_attribute("bring.pull.added",            outcome.added)
        span.set_attribute("bring.pull.reactivated",      outcome.reactivated)
        span.set_attribute("bring.pull.marked_purchased", outcome.marked_purchased)
        span.set_attribute("bring.pull.unchanged",        outcome.unchanged)
      end
      Telemetry.counter("pantria.bring.pull_total",
                        description: "Bring -> Homestead pull operations").add(1)
      Telemetry.counter("pantria.bring.items_synced_total",
                        description: "Grocery rows touched by a Bring pull (added/reactivated/purchased)")
               .add(outcome.total_changed)
    end

    # Bring's list payload uses { name, specification }; we only key on name.
    def names(items)
      Array(items).map { |i| i["name"].to_s.strip }.reject(&:empty?).uniq
    end

    # @return [:added, :reactivated, :unchanged]
    def sync_active(name)
      product = @household.products.match_by_term(name).first
      gi      = locate_grocery_item(name, product)

      if gi.nil?
        @household.grocery_items.create!(
          product:  product,
          name:     (product ? nil : name),
          status:   "needed",
          quantity: 1
        )
        :added
      elsif gi.status != "needed"
        gi.update!(status: "needed", purchased_at: nil)
        :reactivated
      else
        :unchanged
      end
    end

    # @return [Boolean] true if a row was flipped
    def sync_recent?(name)
      product = @household.products.match_by_term(name).first
      gi      = locate_grocery_item(name, product, status: "needed")
      return false unless gi

      gi.update!(status: "purchased", purchased_at: Time.current)
      true
    end

    # Look for an existing GroceryItem by product link (when matched)
    # OR by free-form name when no product matched. Optional status
    # filter (used by sync_recent? which only cares about open rows).
    def locate_grocery_item(name, product, status: nil)
      scope = @household.grocery_items
      scope = scope.where(status: status) if status
      if product
        scope.find_by(product: product)
      else
        scope.where(product_id: nil).find_by("LOWER(name) = ?", name.downcase)
      end
    end
  end
end
