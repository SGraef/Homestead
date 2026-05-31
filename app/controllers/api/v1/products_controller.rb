# frozen_string_literal: true
# typed: true

module Api
  module V1
    class ProductsController < BaseController
      before_action :set_product, only: %i[show update destroy]

      def index
        page, limit = pagination_params
        scope = policy_scope(current_household.products).order(:name).limit(limit).offset((page - 1) * limit)
        render json: scope.map { |p| ProductSerializer.call(p) }
      end

      def show
        authorize @product
        render json: ProductSerializer.call(@product, include_prices: true)
      end

      def create
        product = current_household.products.new(product_params)
        authorize product
        product.save!
        render json: ProductSerializer.call(product), status: :created
      end

      def update
        authorize @product
        @product.update!(product_params)
        render json: ProductSerializer.call(@product)
      end

      def destroy
        authorize @product
        @product.destroy
        head :no_content
      end

      # GET /api/v1/products/lookup?barcode=...
      #
      # Lookup precedence:
      #   200 OK   { source: "local",  product: {…} }     local match in household
      #   200 OK   { source: "remote", suggestion: {…} }  external suggestion (Open Food Facts, …)
      #   404      { error: "Unknown barcode" }           neither hit
      #
      # The remote case is *not* persisted; clients can POST the suggestion to
      # `/api/v1/products` to import it into the household catalog.
      def lookup
        code    = params[:barcode].to_s.strip
        product = current_household.products.by_barcode(code).first
        if product
          return render(json: { source:  "local",
                                product: ProductSerializer.call(product, include_prices: true) })
        end

        remote = BarcodeLookup.call(code)
        return render_error(:not_found, "Unknown barcode") unless remote

        render json: { source: "remote", suggestion: remote.to_h }
      end

      private

      def set_product
        @product = current_household.products.find(params[:id])
      end

      def product_params
        params.require(:product).permit(:name, :brand, :barcode, :unit, :category, :notes)
      end
    end
  end
end
