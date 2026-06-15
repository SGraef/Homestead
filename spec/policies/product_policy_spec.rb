# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe ProductPolicy do
  subject(:policy) { described_class.new(user, product) }

  let(:user)         { create(:user) }
  let(:other_user)   { create(:user) }
  let(:household)    { create(:household, admin: user) }
  let(:product)      { create(:product, household: household) }

  it "lets a household member read the product" do
    expect(policy.show?).to be true
  end

  it "lets any authenticated user read (single household, no cross-tenant gatekeeping)" do
    expect(described_class.new(other_user, product).show?).to be true
  end

  it "rejects unauthenticated access" do
    expect { described_class.new(nil, product) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it "only admins of the single household may destroy" do
    other_member = create(:user)
    Membership.create!(user: other_member, household: household, role: "member")
    expect(described_class.new(other_member, product).destroy?).to be false
    expect(described_class.new(user, product).destroy?).to be true
  end
end
