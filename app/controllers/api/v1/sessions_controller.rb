# frozen_string_literal: true
# typed: false

module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_api_user!, only: :create

      # POST /api/v1/sessions
      # @param email [String]
      # @param password [String]
      # @return [Hash] { token: "...", user: {...} }
      def create
        user = User.find_by(email: params[:email].to_s.downcase.strip)
        return render_error(:unauthorized, "Invalid credentials") unless user&.valid_password?(params[:password].to_s)

        token = user.api_tokens.create!(name: params[:device_name].presence || "api")
        render json: {
          token: token.plaintext,
          user:  { id: user.id, email: user.email, name: user.name }
        }, status: :created
      end

      # DELETE /api/v1/sessions
      def destroy
        token = request.headers["Authorization"].to_s.split(" ", 2).last
        api_token = ApiToken.authenticate(token)
        api_token&.revoke!
        head :no_content
      end
    end
  end
end
