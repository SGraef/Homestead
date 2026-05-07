# frozen_string_literal: true
# typed: false

module AuthHelpers
  def api_login(user)
    token = user.api_tokens.create!(name: "spec")
    { "Authorization" => "Bearer #{token.plaintext}" }
  end

  def login_via_post(user, password = "password123")
    post login_path, params: { email: user.email, password: password }
  end
end
