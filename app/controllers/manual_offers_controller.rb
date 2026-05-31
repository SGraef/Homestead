# frozen_string_literal: true
# typed: false

# CRUD for hand-typed offers — the fallback for retailers that aren't
# carried by any aggregator we scrape (Edeka, regional Aldi groups in
# parts of DE, …). Persists as `Offer` rows with `source: "manual"`,
# distinguished from synced offers in the unique `(household_id, source,
# external_id)` index.
#
# Manual offers participate in the same blocklist + retailer filter as
# synced offers (the filters live on Offer queries, not on the syncer),
# so the user can still hide them via the same UI -- though the natural
# action on a typo'd entry is Edit/Delete from the offer card itself.
class ManualOffersController < ApplicationController
  before_action :ensure_household
  before_action :set_offer, only: %i[edit update destroy]

  def new
    @offer = current_household.offers.new(
      source:        "manual",
      external_id:   SecureRandom.uuid,
      currency:      "EUR",
      retailer_name: nil,
      valid_from:    Date.current,
      valid_until:   Date.current + 7
    )
  end

  def edit; end

  def create
    @offer = current_household.offers.new(offer_params.merge(
                                            source:      "manual",
                                            external_id: SecureRandom.uuid,
                                            currency:    "EUR"
                                          ))

    if @offer.save
      redirect_to offers_path, notice: t("offer.manual.flash.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @offer.update(offer_params)
      redirect_to offers_path, notice: t("offer.manual.flash.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @offer.destroy
    redirect_to offers_path, notice: t("offer.manual.flash.removed")
  end

  private

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end

  # Manual entries are only ever created/edited via this controller, so
  # we scope to source: "manual" defensively -- anyone trying to URL-hack
  # an external Marktguru/kaufda row gets a 404 instead.
  def set_offer
    @offer = current_household.offers.where(source: "manual").find(params[:id])
  end

  # Strong-params + price coercion. The form ships price as a German-
  # formatted string ("1,99") via a number field with step 0.01; we
  # convert to integer cents up front so the AR model only sees the
  # integer column.
  def offer_params
    raw = params.require(:offer).permit(
      :title, :brand, :category, :retailer_name,
      :price_euros, :regular_price_euros,
      :unit, :quantity_text, :image_url,
      :valid_from, :valid_until
    )

    {
      title:               raw[:title],
      brand:               raw[:brand].presence,
      category:            raw[:category].presence,
      retailer_name:       raw[:retailer_name],
      price_cents:         to_cents(raw[:price_euros]),
      regular_price_cents: to_cents(raw[:regular_price_euros]),
      unit:                raw[:unit].presence,
      quantity_text:       raw[:quantity_text].presence,
      image_url:           raw[:image_url].presence,
      valid_from:          raw[:valid_from].presence,
      valid_until:         raw[:valid_until].presence
    }.compact
  end

  def to_cents(value)
    return nil if value.blank?

    BigDecimal(value.to_s.tr(",", ".")).mult(100, 0).round.to_i
  rescue ArgumentError
    nil
  end
end
