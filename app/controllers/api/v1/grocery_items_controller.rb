# frozen_string_literal: true
# typed: true

module Api
  module V1
    class GroceryItemsController < BaseController
      before_action :set_item, only: %i[show update destroy purchase]

      def index
        scope = policy_scope(current_household.grocery_items).includes(:product, :store)
        scope = scope.where(status: params[:status]) if params[:status].present?
        render json: scope.map { |i| GroceryItemSerializer.call(i) }
      end

      def show
        authorize @item
        render json: GroceryItemSerializer.call(@item)
      end

      def create
        item = current_household.grocery_items.new(item_params)
        authorize item
        item.save!
        render json: GroceryItemSerializer.call(item), status: :created
      end

      def update
        authorize @item
        @item.update!(item_params)
        render json: GroceryItemSerializer.call(@item)
      end

      def destroy
        authorize @item
        @item.destroy
        head :no_content
      end

      def purchase
        authorize @item, :update?
        storage_item = @item.mark_purchased!(
          store: current_household.stores.find_by(id: params[:store_id]),
          paid_amount: params[:paid_amount],
          expires_on: params[:expires_on],
          location: params[:location].presence || "pantry"
        )
        render json: {
          grocery_item: GroceryItemSerializer.call(@item),
          storage_item: StorageItemSerializer.call(storage_item)
        }
      end

      # POST /api/v1/grocery_items/scan_purchase
      def scan_purchase
        barcode = params[:barcode].to_s.strip
        product = current_household.products.by_barcode(barcode).first
        return render_error(:not_found, "Unknown barcode") unless product

        item = current_household.grocery_items.needed.find_by(product: product) ||
               current_household.grocery_items.create!(product: product, quantity: 1)
        authorize item, :update?
        storage_item = item.mark_purchased!(store: current_household.stores.find_by(id: params[:store_id]))
        render json: {
          grocery_item: GroceryItemSerializer.call(item),
          storage_item: StorageItemSerializer.call(storage_item)
        }, status: :created
      end

      private

      def set_item
        @item = current_household.grocery_items.find(params[:id])
      end

      def item_params
        params.require(:grocery_item).permit(:product_id, :store_id, :quantity, :status)
      end
    end
  end
end
