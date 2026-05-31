# frozen_string_literal: true
# typed: false

# Manage the per-household offer blocklist. Visible inline on /offers
# under "Blocked patterns" -- this controller handles add/remove.
#
# On create, also wipe any already-stored offer that matches the new
# pattern so the user immediately sees the effect without a re-sync.
class OfferBlocklistEntriesController < ApplicationController
  before_action :ensure_household

  def create
    pattern = params.dig(:entry, :pattern).to_s.strip
    reason  = params.dig(:entry, :reason).to_s.strip

    if pattern.empty?
      redirect_to offers_path, alert: t("offer.blocklist.empty_pattern")
      return
    end

    entry = current_household.offer_blocklist_entries
                             .find_or_initialize_by(pattern: pattern)
    entry.reason = reason.presence
    if entry.save
      removed = remove_matching_offers(entry)
      redirect_to offers_path,
                  notice: t("offer.blocklist.added", pattern: entry.pattern, removed: removed)
    else
      redirect_to offers_path,
                  alert: entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    entry = current_household.offer_blocklist_entries.find(params[:id])
    entry.destroy
    redirect_to offers_path,
                notice: t("offer.blocklist.removed", pattern: entry.pattern)
  end

  private

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  # Drop already-synced offers whose title matches the new pattern.
  # Avoids "I just blocked 'cat food' but Whiskas is still on the page
  # until the next 4am cron tick".
  def remove_matching_offers(entry)
    needle = entry.normalized
    return 0 if needle.empty?

    current_household.offers
                     .where("LOWER(title) LIKE ?", "%#{Offer.sanitize_sql_like(needle)}%")
                     .delete_all
  end
end
