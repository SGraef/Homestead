# frozen_string_literal: true
# typed: true

module Api
  module V1
    class StoresController < BaseController
      before_action :set_store, only: %i[show update destroy]

      def index
        render json: policy_scope(current_household.stores).order(:name).map { |s| StoreSerializer.call(s) }
      end

      def show
        authorize @store
        render json: StoreSerializer.call(@store)
      end

      def create
        store = current_household.stores.new(store_params)
        authorize store
        store.save!
        render json: StoreSerializer.call(store), status: :created
      end

      def update
        authorize @store
        @store.update!(store_params)
        render json: StoreSerializer.call(@store)
      end

      def destroy
        authorize @store
        @store.destroy
        head :no_content
      end

      private

      def set_store
        @store = current_household.stores.find(params[:id])
      end

      def store_params
        params.require(:store).permit(:name, :chain, :address, :url)
      end
    end
  end
end
