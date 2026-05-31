# frozen_string_literal: true
# typed: true

# Catalog entry for an item the household consumes. A product can group
# several brand SKUs together: the "primary" barcode lives on this row
# ({#barcode}); additional brand variants live as {ProductBarcode} rows so
# scanning any of them resolves to the same Product (the "type" -- Butter,
# Toast, …).
class Product < ApplicationRecord
  UNITS = %w[pcs g kg ml l portions].freeze

  # Maps every storage unit to a canonical "comparison" unit (the unit you
  # actually want to *price per* on a shelf-tag), plus the multiplier that
  # converts the per-storage-unit cents the model holds into the per-canonical
  # cents.
  #
  #   product.unit  → canonical unit       multiplier (× per-storage cents)
  #   ----------------------------------------------------------------------
  #   "g"           → "kg"                 1000  (price/g × 1000 = price/kg)
  #   "kg"          → "kg"                 1
  #   "ml"          → "l"                  1000
  #   "l"           → "l"                  1
  #   "pcs"         → "piece"              1
  NORMALIZED_UNITS = {
    "g"        => { unit: "kg",      multiplier: 1000 },
    "kg"       => { unit: "kg",      multiplier: 1 },
    "ml"       => { unit: "l",       multiplier: 1000 },
    "l"        => { unit: "l",       multiplier: 1 },
    "pcs"      => { unit: "piece",   multiplier: 1 },
    "portions" => { unit: "portion", multiplier: 1 }
  }.freeze

  belongs_to :household
  has_many :prices, dependent: :destroy
  has_many :stores, through: :prices
  has_many :storage_items, dependent: :destroy
  has_many :grocery_items, dependent: :destroy
  has_many :product_barcodes, dependent: :destroy
  # Receipts are historical -- keep their line items around with `parsed_name`
  # for audit and just unlink the (now-deleted) product. ReceiptLineItem's
  # `belongs_to :product, optional: true` makes nullify safe.
  has_many :receipt_line_items, dependent: :nullify
  accepts_nested_attributes_for :product_barcodes,
                                allow_destroy: true,
                                reject_if:     ->(attrs) { attrs["barcode"].to_s.gsub(/\D/, "").blank? }

  validates :name, presence: true, length: { maximum: 200 }
  validates :unit, inclusion: { in: UNITS }
  validates :barcode,
            uniqueness: { scope: :household_id, allow_nil: true },
            format:     { with: /\A\d{8,14}\z/, allow_nil: true }

  # Match either the primary barcode column or any alternate barcode row.
  # Used by the scan / lookup flow.
  scope :by_barcode, lambda { |code|
    code = code.to_s.strip
    next none if code.empty?

    where(barcode: code)
      .or(where(id: ProductBarcode.where(barcode: code).select(:product_id)))
      .distinct
  }

  # Every barcode known for this product (primary + alternates), de-duped.
  # @return [Array<String>]
  def all_barcodes
    ([barcode] + product_barcodes.pluck(:barcode)).compact_blank.uniq
  end

  # All brand labels for this product (primary + alternates).
  # @return [Array<String>]
  def all_brands
    ([brand] + product_barcodes.pluck(:brand)).compact_blank.uniq
  end

  # Cheapest currently-known price across all stores in the household.
  # @return [Price, nil]
  def cheapest_price
    prices.order(amount_cents: :asc, observed_on: :desc).first
  end

  # Latest observed price for `store`.
  # @param store [Store]
  # @return [Price, nil]
  def latest_price_at(store)
    prices.where(store: store).order(observed_on: :desc).first
  end

  # @return [String] one of "kg", "l", "piece" — the unit prices should be
  #   normalized against on the UI ("€/kg", "€/l", "€/Stück").
  def normalized_unit
    NORMALIZED_UNITS.dig(unit, :unit) || "piece"
  end

  # @return [Integer] cents per *one storage unit* (g, ml, pcs, …) → cents
  #   per *normalized unit* (kg, l, piece). Multiply Price#amount_cents by
  #   this to get the value the shelf tag would show.
  def normalized_price_multiplier
    NORMALIZED_UNITS.dig(unit, :multiplier) || 1
  end
end
