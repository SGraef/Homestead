# frozen_string_literal: true
# typed: true

# An entry on the household's grocery list. After purchase the item is
# typically converted into a {StorageItem} via {#mark_purchased!}.
class GroceryItem < ApplicationRecord
  STATUSES = %w[needed purchased cancelled].freeze

  belongs_to :household
  belongs_to :product
  belongs_to :store, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :quantity, numericality: { greater_than: 0 }

  scope :needed,    -> { where(status: "needed") }
  scope :purchased, -> { where(status: "purchased") }

  # ---- Bring! integration ------------------------------------------------
  # Status transitions push (needed) or remove (anything else) on the
  # household's Bring! list. The job no-ops when Bring isn't wired up, so
  # these callbacks are safe to fire unconditionally.
  after_create_commit  :enqueue_bring_create
  after_update_commit  :enqueue_bring_update
  before_destroy       :remember_for_bring
  after_destroy_commit :enqueue_bring_destroy

  # Wrap pull-time writes (Bring -> Pantria) in this so the after-commit
  # callbacks don't echo the change right back to Bring (Pantria -> Bring),
  # which would loop forever. Thread-local because ActiveJob workers are
  # threaded.
  def self.without_bring_sync
    prev = Thread.current[:pantria_skip_bring_sync]
    Thread.current[:pantria_skip_bring_sync] = true
    yield
  ensure
    Thread.current[:pantria_skip_bring_sync] = prev
  end

  def self.bring_sync_skipped?
    Thread.current[:pantria_skip_bring_sync] == true
  end

  # Marks the item as purchased and creates a corresponding {StorageItem} so
  # the household's pantry reflects the new stock.
  #
  # @param store [Store, nil] the store the item was purchased at
  # @param paid_amount [Numeric, String, nil] price actually paid (major units)
  # @param expires_on [Date, nil] optional expiry date for the new storage item
  # @param location [Location, String, nil] target location: a Location
  #   record, a kind string ("pantry"/"fridge"/...) which is resolved against
  #   the household, or nil (defaults to the household's pantry-kind one).
  # @return [StorageItem] the newly-created storage item
  def mark_purchased!(store: nil, paid_amount: nil, expires_on: nil, location: nil)
    transaction do
      assign_attributes(
        status:        "purchased",
        purchased_at:  Time.current,
        store:         store || self.store,
        paid_amount_cents: paid_amount && (BigDecimal(paid_amount.to_s) * 100).to_i,
        paid_currency: paid_amount ? "EUR" : nil
      )
      save!

      household.storage_items.create!(
        product:    product,
        quantity:   quantity,
        location:   resolve_location(location),
        expires_on: expires_on
      )
    end
  end

  private

  def resolve_location(value)
    case value
    when Location       then value
    when String, Symbol then household.locations.find_by(kind: value.to_s) ||
                              household.default_storage_location
    else                     household.default_storage_location
    end
  end

  def enqueue_bring_create
    return if self.class.bring_sync_skipped?
    return unless household.bring_connected?
    return unless status == "needed"

    SyncGroceryToBringJob.perform_later(household_id, action: "push", name: bring_name)
  end

  def enqueue_bring_update
    return if self.class.bring_sync_skipped?
    return unless household.bring_connected?
    return unless saved_change_to_status?

    action = status == "needed" ? "push" : "remove"
    SyncGroceryToBringJob.perform_later(household_id, action: action, name: bring_name)
  end

  # Capture the product name BEFORE destroy runs (the association is gone
  # afterwards if the product was destroyed in the same transaction).
  def remember_for_bring
    @bring_destroy_name = bring_name
  end

  def enqueue_bring_destroy
    return if self.class.bring_sync_skipped?
    return unless household.bring_connected?
    return if @bring_destroy_name.blank?

    SyncGroceryToBringJob.perform_later(household_id, action: "remove", name: @bring_destroy_name)
  end

  def bring_name
    product&.name.to_s.strip
  end
end
