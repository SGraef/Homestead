# frozen_string_literal: true
# typed: true

# Read-only aggregator over confirmed receipts. Powers the /expenses page and
# the dashboard "this month" widget. No persistent state -- everything is
# computed from {Receipt#subtotal_cents}, {Receipt#purchased_on} and the
# linked {ReceiptLineItem#parsed_total_cents} + {Product#category}.
#
# Per month we expose:
#   - `total_cents`           — receipts.subtotal_cents (what was actually paid)
#   - `by_category`           — line totals grouped by Product.category, plus
#                               an `OTHER` bucket that rolls up confirmed-receipt
#                               line items that never became products (skipped
#                               lines, deposits, OCR noise the user didn't map).
#   - `uncategorized_cents`   — residual gap between the receipt subtotal and
#                               the sum of all line items above (rounding,
#                               taxes added back, etc.)
class ExpenseReport
  UNCATEGORIZED = "uncategorized"

  # Bucket for confirmed-receipt line items with no linked product
  # (skipped lines, OCR-only rows, etc). Surfaces in #by_category.
  OTHER = "other"

  Month = Struct.new(:key, :label, :total_cents, :by_category, :uncategorized_cents,
                     keyword_init: true) do
    def categorized_cents = by_category.values.sum

    # Top N categories by spend. Always includes "uncategorized" as a final
    # bucket if there's a residual amount.
    def top_categories(limit: 5)
      sorted = by_category.sort_by { |_, c| -c }.first(limit).to_h
      sorted[UNCATEGORIZED] = uncategorized_cents if uncategorized_cents.positive?
      sorted
    end
  end

  # @param household [Household]
  # @param months [Integer] window size in months (rolling)
  def initialize(household:, months: 6)
    @household = household
    @window    = months.to_i.clamp(1, 24)
  end

  # @return [Array<Month>] newest month first
  def months
    @months ||= build_months
  end

  # @return [Month, nil] aggregate for the current calendar month
  def current_month
    months.find { |m| m.key == Date.current.strftime("%Y-%m") } ||
      Month.new(key:                Date.current.strftime("%Y-%m"),
                label:              I18n.l(Date.current, format: "%B %Y"),
                total_cents:        0,
                by_category:        {},
                uncategorized_cents: 0)
  end

  private

  def build_months
    since = (Date.current.beginning_of_month - (@window - 1).months)

    totals     = monthly_totals(since)
    categories = monthly_by_category(since)
    others     = monthly_other(since)

    keys = (totals.keys + categories.keys.map(&:first) + others.keys).uniq.sort.reverse

    keys.map do |key|
      total       = totals[key].to_i
      by_category = categories.select { |(m, _), _| m == key }.transform_keys { |(_, c)| c }
      other_cents = others[key].to_i
      by_category[OTHER] = other_cents if other_cents.positive?
      accounted   = by_category.values.sum
      Month.new(
        key:                 key,
        label:               format_label(key),
        total_cents:         total,
        by_category:         by_category,
        uncategorized_cents: [total - accounted, 0].max
      )
    end
  end

  def monthly_totals(since)
    @household.receipts
              .where(status: "confirmed")
              .where("purchased_on >= ?", since)
              .where.not(purchased_on: nil)
              .group(month_expr_for(:purchased_on, table: :receipts))
              .sum(:subtotal_cents)
  end

  def monthly_by_category(since)
    ReceiptLineItem
      .joins(:receipt, :product)
      .where(receipts: { household_id: @household.id, status: "confirmed" })
      .where("receipts.purchased_on >= ?", since)
      .where.not(receipts: { purchased_on: nil })
      .where(status: %w[matched created])
      .where.not(parsed_total_cents: nil)
      .group(month_expr_for(:purchased_on, table: :receipts),
             category_expr)
      .sum(:parsed_total_cents)
  end

  # Sum of confirmed-receipt line items that never got linked to a product
  # (skipped/ignored lines, OCR-only rows). Rolled into #by_category under
  # the {OTHER} key so they show up alongside the product categories in
  # the splitting -- previously they only showed up implicitly inside
  # {Month#uncategorized_cents}.
  def monthly_other(since)
    ReceiptLineItem
      .joins(:receipt)
      .where(receipts: { household_id: @household.id, status: "confirmed" })
      .where("receipts.purchased_on >= ?", since)
      .where.not(receipts: { purchased_on: nil })
      .where(product_id: nil)
      .where.not(parsed_total_cents: nil)
      .group(month_expr_for(:purchased_on, table: :receipts))
      .sum(:parsed_total_cents)
  end

  def month_expr_for(column, table:)
    Arel.sql("DATE_FORMAT(`#{table}`.`#{column}`, '%Y-%m')")
  end

  def category_expr
    # Treat NULL and empty-string categories the same.
    Arel.sql("COALESCE(NULLIF(`products`.`category`, ''), '#{UNCATEGORIZED}')")
  end

  def format_label(key)
    year, month = key.split("-").map(&:to_i)
    I18n.l(Date.new(year, month, 1), format: "%B %Y")
  rescue ArgumentError, Date::Error
    key
  end
end
