# frozen_string_literal: true
# typed: false

# Manage the per-household offer watchlist. Lives inline on /offers under
# "Watchlist" -- this controller handles add/remove. Watchlist entries
# don't filter, they re-rank (matched offers sort first + get a visual
# highlight); the actual ordering happens in {OffersController#index}.
class OfferWatchlistEntriesController < ApplicationController
  before_action :ensure_household

  def create
    pattern = params.dig(:entry, :pattern).to_s.strip
    if pattern.empty?
      redirect_to offers_path, alert: t("offer.watchlist.empty_pattern")
      return
    end

    entry = current_household.offer_watchlist_entries
                             .find_or_initialize_by(pattern: pattern)
    if entry.save
      redirect_to offers_path,
                  notice: t("offer.watchlist.added", pattern: entry.pattern)
    else
      redirect_to offers_path, alert: entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    entry = current_household.offer_watchlist_entries.find(params[:id])
    entry.destroy
    redirect_to offers_path,
                notice: t("offer.watchlist.removed", pattern: entry.pattern)
  end

  private

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end
end
