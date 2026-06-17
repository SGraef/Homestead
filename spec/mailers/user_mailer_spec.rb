# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe UserMailer do
  let(:user) { build_stubbed(:user, email: "alice@example.com", name: "Alice") }

  before { I18n.locale = :en }
  after  { I18n.locale = I18n.default_locale }

  describe "#activation_needed_email" do
    subject(:mail) { described_class.activation_needed_email(user) }

    before { allow(user).to receive(:activation_token).and_return("act-token-123") }

    it "is addressed to the user with the right subject" do
      expect(mail.to).to eq([user.email])
      expect(mail.subject).to eq("Please activate your Homestead account")
      expect(mail.from).to include("no-reply@pantria.local")
    end

    it "embeds the activation URL" do
      expect(mail.body.encoded).to include("/activate/act-token-123")
    end
  end

  describe "#activation_success_email" do
    subject(:mail) { described_class.activation_success_email(user) }

    it "uses the success subject and links to login" do
      expect(mail.subject).to eq("Your Homestead account is active")
      expect(mail.body.encoded).to include("/login")
    end
  end

  describe "#reset_password_email" do
    subject(:mail) { described_class.reset_password_email(user) }

    before { allow(user).to receive(:reset_password_token).and_return("reset-tok-9") }

    it "embeds the reset URL with the token" do
      expect(mail.subject).to eq("Homestead password reset")
      expect(mail.body.encoded).to include("/password_resets/reset-tok-9/edit")
    end
  end
end
