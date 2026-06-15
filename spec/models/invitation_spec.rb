# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Invitation do
  let(:household) { create(:household) }

  describe ".invite!" do
    it "creates a pending invitation with a one-time plaintext token (digest stored)" do
      inv = described_class.invite!(household: household, email: " New@Example.com ", role: "member")

      expect(inv).to be_persisted
      expect(inv.email).to eq("new@example.com")
      expect(inv.plaintext).to be_present
      expect(inv.token_digest).to eq(Digest::SHA256.hexdigest(inv.plaintext))
      expect(inv.expires_at).to be > Time.current
    end

    it "refreshes an existing pending invitation instead of duplicating it" do
      first      = described_class.invite!(household: household, email: "x@example.com", role: "member")
      old_digest = first.token_digest

      again = described_class.invite!(household: household, email: "x@example.com", role: "admin")

      expect(again.id).to eq(first.id)
      expect(again.role).to eq("admin")
      expect(again.token_digest).not_to eq(old_digest)
      expect(household.invitations.pending.count).to eq(1)
    end
  end

  describe ".authenticate" do
    it "finds a pending invitation by its plaintext token" do
      inv = described_class.invite!(household: household, email: "a@example.com", role: "member")
      expect(described_class.authenticate(inv.plaintext)).to eq(inv)
    end

    it "returns nil for blank, unknown, expired or accepted tokens" do
      inv   = described_class.invite!(household: household, email: "a@example.com", role: "member")
      token = inv.plaintext

      expect(described_class.authenticate("")).to be_nil
      expect(described_class.authenticate("not-a-real-token")).to be_nil

      inv.update!(expires_at: 1.hour.ago)
      expect(described_class.authenticate(token)).to be_nil

      inv.update!(expires_at: 1.day.from_now, accepted_at: Time.current)
      expect(described_class.authenticate(token)).to be_nil
    end
  end

  describe "#accept!" do
    it "creates an active user + membership and consumes the invitation" do
      inv  = described_class.invite!(household: household, email: "join@example.com", role: "admin")
      user = inv.accept!(name: "Joiner", password: "password123", password_confirmation: "password123")

      expect(user.activation_state).to eq("active")
      expect(user.email).to eq("join@example.com")
      expect(household.memberships.find_by(user: user).role).to eq("admin")
      expect(inv.reload).to be_accepted
    end

    it "is single-use" do
      inv = described_class.invite!(household: household, email: "join@example.com", role: "member")
      inv.accept!(name: "J", password: "password123", password_confirmation: "password123")

      expect do
        inv.accept!(name: "J", password: "password123", password_confirmation: "password123")
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "rolls back and raises on an invalid password, leaving no user" do
      inv = described_class.invite!(household: household, email: "join@example.com", role: "member")

      expect do
        inv.accept!(name: "J", password: "short", password_confirmation: "short")
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(User.find_by(email: "join@example.com")).to be_nil
      expect(inv.reload).not_to be_accepted
    end
  end
end
