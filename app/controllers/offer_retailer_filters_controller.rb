# frozen_string_literal: true
# typed: false

# Manages the per-household retailer allow-list for offer sync. UI lives
# inline on /offers next to the blocklist section.
#
# Adding an entry immediately deletes already-stored offers from
# retailers not in the (now non-empty) allow-list, so the user sees the
# effect without having to wait for a re-sync. Removing the last entry
# returns the household to "all retailers" mode.
class OfferRetailerFiltersController < ApplicationController
  before_action :ensure_household

  def create
    retailer = params.dig(:filter, :retailer).to_s.strip
    if retailer.empty?
      redirect_to offers_path, alert: t("offer.retailer_filter.empty_input")
      return
    end

    entry = current_household.offer_retailer_filters
                             .find_or_initialize_by(retailer: retailer)
    if entry.save
      removed = prune_offers_outside_allowlist
      redirect_to offers_path,
                  notice: t("offer.retailer_filter.added",
                            retailer: entry.retailer, removed: removed)
    else
      redirect_to offers_path, alert: entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    entry = current_household.offer_retailer_filters.find(params[:id])
    entry.destroy
    redirect_to offers_path,
                notice: t("offer.retailer_filter.removed", retailer: entry.retailer)
  end

  # PUT /offers/retailers/bulk
  # Replace the entire allow-list with the submitted set. Used by the
  # multi-select checkbox form on /offers. An empty submission clears
  # the allow-list and returns the household to "all retailers".
  def bulk
    incoming = Array(params[:retailers]).map { |r| r.to_s.strip }.uniq.reject(&:empty?)

    OfferRetailerFilter.transaction do
      current_set = current_household.offer_retailer_filters.pluck(:retailer)
      to_delete   = current_set - incoming
      to_create   = incoming    - current_set

      if to_delete.any?
        current_household.offer_retailer_filters
                         .where(retailer: to_delete).delete_all
      end
      to_create.each do |r|
        current_household.offer_retailer_filters.create!(retailer: r)
      end
    end

    removed = prune_offers_outside_allowlist
    redirect_to offers_path,
                notice: t("offer.retailer_filter.bulk_saved",
                          count: incoming.size, removed: removed)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to offers_path, alert: e.message
  end

  private

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end

  # Drop already-stored offers whose retailer (name OR slug) isn't in
  # the allow-list. Empty allow-list => no-op (the syncer also short
  # circuits when filters are empty).
  def prune_offers_outside_allowlist
    filters = current_household.offer_retailer_filters.pluck(:retailer).map(&:downcase)
    return 0 if filters.empty?

    quoted = filters.map { |f| ActiveRecord::Base.connection.quote(f) }.join(",")
    current_household.offers
                     .where("LOWER(retailer_name) NOT IN (#{quoted})")
                     .delete_all
  end
end
