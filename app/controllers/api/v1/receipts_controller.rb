# frozen_string_literal: true
# typed: true

module Api
  module V1
    class ReceiptsController < BaseController
      before_action :set_receipt, only: %i[show confirm destroy reprocess]

      # POST /api/v1/receipts — multipart, field `image`
      # Triggers ProcessReceiptJob synchronously when `?inline=1` so API
      # callers can poll for the parsed result; defaults to async.
      def create
        receipt = current_household.receipts.new(user: current_user)
        receipt.image.attach(params[:image])
        authorize receipt
        receipt.save!

        if params[:inline].present?
          ProcessReceiptJob.perform_now(receipt.id)
        else
          ProcessReceiptJob.perform_later(receipt.id)
        end
        render json: ReceiptSerializer.call(receipt.reload), status: :created
      end

      def index
        scope = policy_scope(current_household.receipts).recent.limit(100)
        render json: scope.map { |r| ReceiptSerializer.call(r) }
      end

      def show
        authorize @receipt
        render json: ReceiptSerializer.call(@receipt, include_lines: true)
      end

      # POST /api/v1/receipts/:id/confirm
      def confirm
        authorize @receipt, :update?
        ReceiptConfirmer.new(receipt: @receipt, user: current_user, params: confirm_params).call
        render json: ReceiptSerializer.call(@receipt.reload, include_lines: true)
      end

      def destroy
        authorize @receipt
        @receipt.destroy
        head :no_content
      end

      # POST /api/v1/receipts/:id/reprocess
      def reprocess
        authorize @receipt, :update?
        unless @receipt.reprocessable?
          return render_error(:unprocessable_entity, "Cannot reprocess a confirmed receipt")
        end

        @receipt.reprocess!
        render json: ReceiptSerializer.call(@receipt.reload, include_lines: true), status: :accepted
      end

      private

      def set_receipt
        @receipt = current_household.receipts.find(params[:id])
      end

      def confirm_params
        params.permit(:store_id, :new_store_name,
                      lines: {}).to_h
      end
    end
  end
end
