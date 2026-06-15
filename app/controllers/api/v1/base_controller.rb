# frozen_string_literal: true
# typed: false

# Base class for all REST API v1 endpoints. Authenticates via the
# `Authorization: Bearer <token>` header against {ApiToken}, exposes
# {#current_user} and {#current_household}, and renders Pundit failures as
# JSON 403s rather than HTML redirects.
module Api
  module V1
    class BaseController < ActionController::API
      include Pundit::Authorization

      before_action :authenticate_api_user!

      rescue_from ActiveRecord::RecordNotFound, with: -> { render_error(:not_found, "Not found") }
      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
      end
      rescue_from Pundit::NotAuthorizedError, with: -> { render_error(:forbidden, "Forbidden") }

      attr_reader :current_user, :current_household

      private

      def authenticate_api_user!
        token = request.headers["Authorization"].to_s.split(" ", 2).last
        api_token = ApiToken.authenticate(token)
        return render_error(:unauthorized, "Invalid token") unless api_token

        api_token.touch_used!
        @current_user      = api_token.user
        @current_household = Household.current
      end

      def render_error(status, message)
        render json: { error: message }, status: status
      end

      def pagination_params
        page  = [params[:page].to_i, 1].max
        limit = params[:per_page].to_i.clamp(25, 100)
        [page, limit]
      end
    end
  end
end
