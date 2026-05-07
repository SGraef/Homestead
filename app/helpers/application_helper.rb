# frozen_string_literal: true
# typed: true

# View helpers used across templates.
module ApplicationHelper
  # @param amount_cents [Integer]
  # @param currency [String]
  # @return [String]
  def format_money(amount_cents, currency = "EUR")
    return "—" unless amount_cents

    "#{currency} #{format('%.2f', amount_cents / 100.0)}"
  end

  # Format a Price as "shelf-tag" value: e.g. "1,99 € / kg" / "0,50 € / Stück".
  # Returns nil when there's nothing meaningful to show (no product / no
  # amount), so callers can fall back to the raw price string.
  #
  # @param price [Price]
  # @return [String, nil]
  def normalized_price(price)
    amount = price&.amount_per_normalized_unit
    return nil unless amount

    unit_label = t("product.normalized_units.#{price.normalized_unit}",
                   default: price.normalized_unit)
    "#{number_to_currency(amount, unit: price.currency)} / #{unit_label}"
  end
end
