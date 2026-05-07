# frozen_string_literal: true
# typed: true

module Api
  module V1
    class PricesController < BaseController
      before_action :set_product
      before_action :set_price, only: %i[update destroy]

      def index
        render json: @product.prices.includes(:store).recent.map { |p| PriceSerializer.call(p) }
      end

      def create
        price = @product.prices.new(price_params)
        authorize price
        price.save!
        render json: PriceSerializer.call(price), status: :created
      end

      def update
        authorize @price
        @price.update!(price_params)
        render json: PriceSerializer.call(@price)
      end

      def destroy
        authorize @price
        @price.destroy
        head :no_content
      end

      private

      def set_product
        @product = current_household.products.find(params[:product_id])
      end

      def set_price
        @price = @product.prices.find(params[:id])
      end

      def price_params
        params.require(:price).permit(:store_id, :amount_cents, :currency, :observed_on, :source)
      end
    end
  end
end
