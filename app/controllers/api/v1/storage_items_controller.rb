# frozen_string_literal: true
# typed: true

module Api
  module V1
    class StorageItemsController < BaseController
      before_action :set_item, only: %i[show update destroy]

      def index
        scope = policy_scope(current_household.storage_items)
                  .includes(:product, :location).order(:expires_on)
        scope = scope.expiring_within(params[:expiring_within].to_i) if params[:expiring_within].present?

        if params[:location_id].present?
          scope = scope.where(location_id: params[:location_id])
        elsif params[:location_kind].present?
          scope = scope.joins(:location).where(locations: { kind: params[:location_kind] })
        end

        render json: scope.map { |i| StorageItemSerializer.call(i) }
      end

      def show
        authorize @item
        render json: StorageItemSerializer.call(@item)
      end

      def create
        item = current_household.storage_items.new(item_params)
        authorize item
        item.save!
        render json: StorageItemSerializer.call(item), status: :created
      end

      def update
        authorize @item
        @item.update!(item_params)
        render json: StorageItemSerializer.call(@item)
      end

      def destroy
        authorize @item
        @item.destroy
        head :no_content
      end

      private

      def set_item
        @item = current_household.storage_items.find(params[:id])
      end

      def item_params
        params.require(:storage_item)
              .permit(:product_id, :quantity, :location_id,
                      :expires_on, :opened_on, :frozen_on)
      end
    end
  end
end
