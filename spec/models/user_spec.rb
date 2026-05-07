# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe User do
  it { is_expected.to have_many(:memberships) }
  it { is_expected.to have_many(:households).through(:memberships) }
  it { is_expected.to validate_presence_of(:email) }

  it "downcases the email before save" do
    user = create(:user, email: "MIXED@Example.com")
    expect(user.email).to eq("mixed@example.com")
  end
end
