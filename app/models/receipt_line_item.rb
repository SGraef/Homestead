# frozen_string_literal: true
# typed: true

# One line of a {Receipt}. Starts as `unmatched` -- after the user confirms,
# it transitions to `matched` (linked to an existing Product) or `created`
# (a new Product was made from it). `ignored` lines are skipped.
class ReceiptLineItem < ApplicationRecord
  STATUSES = %w[unmatched matched created ignored].freeze

  belongs_to :receipt
  belongs_to :product, optional: true

  validates :status, inclusion: { in: STATUSES }

  # @return [BigDecimal, nil]
  def parsed_total
    return nil unless parsed_total_cents

    BigDecimal(parsed_total_cents.to_s) / 100
  end
end
