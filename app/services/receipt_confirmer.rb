# frozen_string_literal: true
# typed: true

# Applies a user's confirmation of a parsed {Receipt}, writing {Store},
# {Product}, {Price} -- and optionally {StorageItem} -- records into the
# household.
#
# Expected params shape (from the confirm form):
#
#   { store_id: 7,                  # OR
#     new_store_name: "REWE Mitte", #   creates the store if missing
#
#     lines: {
#       "12" => { action: "create",  name: "Whole Milk 1L", unit: "l",
#                                    barcode: "4006381333924",
#                                    to_storage: "1",            # per-line opt-in, default on
#                                    location:  "fridge",        # per-line, falls back to "pantry"
#                                    expires_on: "2026-05-13" },
#       "13" => { action: "match",   product_id: 42,
#                                    to_storage: "0",            # bought, but consumed immediately
#                                    location: "freezer" },
#       "14" => { action: "skip" }
#     } }
class ReceiptConfirmer
  DEFAULT_LOCATION = "pantry"

  def initialize(receipt:, user:, params:)
    @receipt   = receipt
    @user      = user
    @household = receipt.household
    @params    = params
  end

  # @return [Receipt]
  def call
    Receipt.transaction do
      store = resolve_store
      @receipt.update!(store: store)

      decisions.each do |line_id, decision|
        line = @receipt.receipt_line_items.find(line_id)
        apply(line, decision)
      end

      @receipt.update!(status: "confirmed", confirmed_at: Time.current)
    end
    @receipt
  end

  private

  def decisions
    raw = @params[:lines]
    return {} if raw.blank?

    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
  end

  def resolve_store
    if @params[:store_id].present?
      @household.stores.find(@params[:store_id])
    else
      name = (@params[:new_store_name].presence || @receipt.detected_store_name).to_s.strip
      raise ArgumentError, "Store name required" if name.empty?

      @household.stores.find_or_create_by!(name: name)
    end
  end

  def apply(line, decision)
    case decision[:action].to_s
    when "skip"
      line.update!(status: "ignored")
    when "match"
      product = match_existing(line, decision)
      mark_grocery_purchased(product)
      store_line(line, product, decision)
    when "create"
      product = create_new(line, decision)
      mark_grocery_purchased(product)
      store_line(line, product, decision)
    end
  end

  # If the just-confirmed product is on the household's grocery list as
  # "needed", flip those entries to "purchased". The default grocery list
  # view hides purchased rows, so this effectively "removes from the
  # shopping list", and the after_update_commit callback also tells Bring!
  # to move the item out of the active list. Going through `update!` (not
  # `mark_purchased!`) avoids creating a duplicate StorageItem -- the
  # receipt flow already creates one in {#store_line} when the line's
  # to_storage box is checked.
  def mark_grocery_purchased(product)
    return unless product

    @household.grocery_items
              .where(product: product, status: "needed")
              .find_each do |gi|
      gi.update!(status: "purchased", purchased_at: Time.current)
    end
  end

  def match_existing(line, decision)
    product = @household.products.find(decision[:product_id])
    record_price(product, line, decision)
    record_synonym(product, line, decision)
    line.update!(product: product, status: "matched")
    product
  end

  def create_new(line, decision)
    product = @household.products.create!(
      name:     decision[:name].presence || line.parsed_name,
      brand:    decision[:brand].presence,
      barcode:  decision[:barcode].presence,
      unit:     decision[:unit].presence || "pcs",
      category: decision[:category].presence
    )
    record_price(product, line, decision)
    record_synonym(product, line, decision)
    line.update!(product: product, status: "created")
    product
  end

  # When the user ticks "add as synonym", store the line's OCR'd
  # parsed_name on the resolved product so the NEXT receipt with the
  # same shorthand auto-resolves without a click. Idempotent — same
  # term twice is a no-op thanks to the per-product unique index.
  def record_synonym(product, line, decision)
    return unless product
    return unless truthy?(decision[:add_synonym])

    term = line.parsed_name.to_s.strip
    return if term.empty?
    return if term.casecmp(product.name).zero? # don't bother with self-synonyms

    normalized = ProductSynonym.normalize(term)
    return if product.product_synonyms.exists?(normalized_term: normalized)

    product.product_synonyms.create!(term: term)
  end

  # Stores the *per-piece* amount (total / pieces, integer-cent rounded) so
  # prices for the same product across stores stay comparable regardless of
  # bulk pack size. The user can override the OCR-parsed total by
  # filling the per-line `amount` input on the confirm form -- handy
  # when the OCR mangled the price or skipped a digit. Without an
  # override we fall back to line.parsed_total_cents; if both are
  # missing we skip the Price write rather than record €0.
  def record_price(product, line, decision)
    return unless product && @receipt.store

    total_cents = parse_amount_cents(decision[:amount]) || line.parsed_total_cents
    return unless total_cents

    pieces          = positive_pieces(decision, line)
    per_piece_cents = (BigDecimal(total_cents) / pieces).round.to_i

    Price.create!(
      product:      product,
      store:        @receipt.store,
      amount_cents: per_piece_cents,
      currency:     @receipt.currency.presence || "EUR",
      observed_on:  @receipt.purchased_on || Date.current,
      source:       "receipt"
    )
  end

  # @return [Integer, nil] amount in integer cents, or nil for blank /
  #   non-numeric / non-positive input. Comma decimals accepted so a
  #   German-keyboard user can type "1,99" directly.
  def parse_amount_cents(raw)
    return nil if raw.blank?

    major = BigDecimal(raw.to_s.tr(",", "."))
    return nil if major <= 0

    (major * 100).round.to_i
  rescue ArgumentError
    nil
  end

  # Pieces (integer or decimal) the user entered on the confirm form. Falls
  # back to the OCR-parsed quantity, then to 1, so a missing or junk input
  # never causes a divide-by-zero or a zeroed-out Price.
  # @return [BigDecimal]
  def positive_pieces(decision, line = nil)
    raw = decision[:pieces].to_s.tr(",", ".").strip
    if raw.present?
      value = BigDecimal(raw)
      return value if value.positive?
    end

    fallback = line&.parsed_quantity.presence || 1
    BigDecimal(fallback.to_s)
  rescue ArgumentError
    BigDecimal("1")
  end

  # Optionally create a StorageItem for the just-confirmed line. The form
  # ships a per-line "to_storage" checkbox that defaults to checked; clearing
  # it means "bought, but consumed immediately -- don't stock". The hidden
  # sibling input ensures unchecked still submits "0".
  def store_line(line, product, decision)
    return unless product
    return unless truthy?(decision[:to_storage])

    @household.storage_items.create!(
      product:    product,
      quantity:   positive_pieces(decision, line),
      location:   line_location(decision),
      expires_on: parse_date(decision[:expires_on])
    )
  end

  # Per-line location can be either a household Location id or a
  # legacy kind string ("pantry"/"fridge"/...). Falls back to the
  # household's default location if the form sent neither.
  # @return [Location]
  def line_location(decision)
    raw = decision[:location].presence
    if raw.to_s.match?(/\A\d+\z/)
      loc = @household.locations.find_by(id: raw.to_i)
      return loc if loc
    end
    if raw.is_a?(String)
      loc = @household.locations.find_by(kind: raw)
      return loc if loc
    end
    @household.default_storage_location
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def truthy?(value)
    %w[1 true yes on].include?(value.to_s.downcase)
  end
end
