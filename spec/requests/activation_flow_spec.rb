# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Activation flow" do
  it "delivers an activation email on signup and activates the user via the token URL" do
    expect do
      post "/registration", params: {
        user: { email: "new@example.com", name: "New",
                password: "password123", password_confirmation: "password123" }
      }
    end.to change { ActionMailer::Base.deliveries.count }.by(1)
                                                         .and change(User, :count).by(1)

    user = User.find_by(email: "new@example.com")
    expect(user.activation_state).to eq("pending")
    expect(user.activation_token).to be_present

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([user.email])
    expect(mail.body.encoded).to include("/activate/#{user.activation_token}")

    get "/activate/#{user.activation_token}"
    expect(response).to redirect_to(login_path)
    expect(user.reload.activation_state).to eq("active")
  end

  it "shows an error for an invalid activation token" do
    get "/activate/totally-bogus"
    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to be_present
  end
end
