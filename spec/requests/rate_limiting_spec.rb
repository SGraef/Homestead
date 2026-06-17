# frozen_string_literal: true
# typed: false

require "rails_helper"

# Rack::Attack is disabled by default in test (see config/initializers/
# rack_attack.rb) so it doesn't leak throttle state across unrelated request
# specs. These examples opt in and clear the in-memory counter around each run.
RSpec.describe "Rate limiting (Rack::Attack)", type: :request do
  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
    example.run
  ensure
    Rack::Attack.cache.store.clear
    Rack::Attack.enabled = false
  end

  describe "POST /login" do
    it "throttles repeated attempts for the same email (5/20s)" do
      6.times do
        post "/login", params: { email: "victim@example.com", password: "wrong" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to be_present
      expect(response.body).to match(/too many requests/i)
    end

    it "does not throttle a single attempt" do
      post "/login", params: { email: "someone@example.com", password: "wrong" }
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end

  describe "POST /api/v1/sessions" do
    it "throttles repeated token issuance from one IP (10/20s) with a JSON 429" do
      11.times do
        post "/api/v1/sessions", params: { email: "a@b.de", password: "x" }, as: :json
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.content_type).to start_with("application/json")
    end
  end

  describe "POST /password_resets" do
    it "throttles reset requests per IP (5/60s) to prevent email bombing" do
      6.times do
        post "/password_resets", params: { email: "target@example.com" }
      end
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
