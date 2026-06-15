# frozen_string_literal: true
# typed: false

class ReceiptsController < ApplicationController
  before_action :ensure_household
  before_action :set_receipt, only: %i[show confirm destroy reprocess]

  def index
    @receipts = policy_scope(current_household.receipts).recent.limit(50)
  end

  def show
    authorize @receipt
    @line_items  = @receipt.receipt_line_items
    @auto_match  = build_auto_match_map(@line_items)
  end

  def new
    @receipt = current_household.receipts.build
    authorize @receipt
  end

  def create
    @receipt = current_household.receipts.build(user: current_user)
    @receipt.image.attach(params.dig(:receipt, :image))
    authorize @receipt

    if @receipt.save
      ProcessReceiptJob.perform_later(@receipt.id)
      redirect_to @receipt, notice: t("notices.receipt_uploaded")
    else
      render :new, status: :unprocessable_content
    end
  end

  def confirm
    authorize @receipt, :update?
    ReceiptConfirmer.new(receipt: @receipt, user: current_user, params: confirm_params).call
    redirect_to @receipt, notice: t("notices.receipt_confirmed")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to @receipt, alert: t("notices.confirm_failed", error: e.message)
  end

  def destroy
    authorize @receipt
    @receipt.destroy
    redirect_to receipts_path, notice: t("notices.receipt_removed")
  end

  # POST /receipts/:id/reprocess -- wipe parsed state, re-enqueue OCR.
  def reprocess
    authorize @receipt, :update?
    return redirect_to(@receipt, alert: t("notices.cannot_reprocess")) unless @receipt.reprocessable?

    @receipt.reprocess!
    redirect_to @receipt, notice: t("notices.receipt_reprocessing")
  end

  private

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_receipt
    @receipt = current_household.receipts.find(params[:id])
  end

  def confirm_params
    params.permit(:store_id, :new_store_name,
                  lines: {}).to_h
  end

  # Pre-resolve every line's parsed_name against the household's product
  # catalogue (primary name OR registered synonym). The view uses this
  # map to default the per-line "action" select to "match" with the
  # matched product preselected — saving the user a dropdown click for
  # every line that's been bought before.
  #
  # @return [Hash{Integer => Product}] keyed by line.id
  def build_auto_match_map(line_items)
    line_items.each_with_object({}) do |line, acc|
      next if line.product_id # already linked from a prior confirmation

      term = line.parsed_name.to_s.strip
      next if term.empty?

      product = current_household.products.match_by_term(term).first
      acc[line.id] = product if product
    end
  end
end
