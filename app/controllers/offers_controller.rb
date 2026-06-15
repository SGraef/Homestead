# frozen_string_literal: true
# typed: false

# Lists currently-running Marktguru offers for the household and exposes a
# manual "Sync now" button. Background sync runs daily via Solid Queue
# (see config/recurring.yml :: sync_all_offers).
class OffersController < ApplicationController
  before_action :ensure_household

  def index
    @postal_code = current_household.postal_code
    scope = current_household.offers.current.ordered
                             .includes(:product, :store)
    if (q = params[:q].presence)
      like = "%#{Offer.sanitize_sql_like(q)}%"
      scope = scope.where("title LIKE ? OR retailer_name LIKE ? OR brand LIKE ?",
                          like, like, like)
    end

    @watch_patterns = current_household.offer_watchlist_entries
                                       .pluck(:pattern).map { |p| p.to_s.downcase }

    # Pull into memory so the watchlist re-rank can run; capped at 200
    # to keep the page bounded.
    offers = scope.limit(200).to_a

    # Group by category. Linked-product category wins when available
    # (user-curated); otherwise the offer's own category from the
    # adapter; otherwise the "no category" bucket which sorts last.
    grouped = offers.group_by { |o| category_for(o) }

    # Within each category: watched first, then preserve the DB ordering
    # (valid_until ASC, price_cents ASC).
    grouped.each_value do |arr|
      arr.sort_by!.with_index do |o, i|
        watched = OfferWatchlistEntry.match?(@watch_patterns, o.title)
        [watched ? 0 : 1, i]
      end
    end

    # Stable category order: named buckets alphabetical, no-category last.
    @offers_by_category = grouped.sort_by do |cat, _|
      [cat.nil? ? 1 : 0, cat.to_s.downcase]
    end
    # Backwards-compatible flat list for any view branch still using it.
    @offers = @offers_by_category.flat_map { |_, arr| arr }
  end

  helper_method :offer_watched?

  # Used by the view to add a `.offer-card--watched` modifier class.
  def offer_watched?(offer)
    return false if @watch_patterns.blank?

    OfferWatchlistEntry.match?(@watch_patterns, offer.title)
  end

  # POST /offers/sync — manual trigger from the page.
  def sync
    if current_household.postal_code.to_s.strip.empty?
      redirect_to offers_path,
                  alert: t("offer.flash.postal_code_required")
      return
    end

    SyncOffersJob.perform_later(current_household.id)
    redirect_to offers_path, notice: t("offer.flash.sync_enqueued")
  end

  # POST /offers/reset — wipe all current_household offers and re-sync
  # from scratch. Useful after switching strategies (broad vs targeted
  # pull) or after Marktguru's API behavior changes -- otherwise stale
  # offers from a previous sync linger until they expire.
  def reset
    current_household.offers.delete_all
    if current_household.postal_code.to_s.strip.present?
      SyncOffersJob.perform_later(current_household.id)
      redirect_to offers_path, notice: t("offer.flash.reset_done")
    else
      redirect_to offers_path, notice: t("offer.flash.reset_cleared")
    end
  end

  # POST /offers/:id/add_to_list — one-click "I want this": creates a
  # {Product} from the offer if it isn't linked to one yet, then adds (or
  # bumps) a {GroceryItem}. The created product persists so future
  # receipts and barcode scans can resolve to it.
  def add_to_list
    offer = current_household.offers.find(params[:id])

    Offer.transaction do
      product = offer.product || create_product_from(offer)
      offer.update!(product: product) if offer.product.nil?
      add_or_bump_grocery_item(product)
    end

    redirect_to offers_path,
                notice: t("offer.flash.added_to_list", title: offer.title)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to offers_path,
                alert: t("offer.flash.add_failed", error: e.message)
  end

  private

  # Category source priority used by /offers grouping: a linked
  # Product's category (user-curated) wins, then the offer's own
  # category populated by the adapter (e.g. Marktguru industry slug),
  # then nil — which the view renders under the "no category" heading
  # at the bottom.
  def category_for(offer)
    cat = offer.product&.category.presence || offer.category.presence
    cat&.strip.presence
  end

  def create_product_from(offer)
    current_household.products.create!(
      name:     offer.title.to_s.strip,
      brand:    offer.brand.presence,
      category: offer.category.presence,
      unit:     offer.unit.presence || "pcs"
    )
  end

  # Same product already needed → just add 1 to the existing row instead
  # of stacking duplicates on the grocery list.
  def add_or_bump_grocery_item(product)
    existing = current_household.grocery_items.find_by(product: product, status: "needed")
    if existing
      existing.update!(quantity: existing.quantity + 1)
    else
      current_household.grocery_items.create!(
        product:  product,
        quantity: 1,
        status:   "needed"
      )
    end
  end

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end
end
