# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe Household do
  describe ".current" do
    it "returns nil when no household exists" do
      expect(described_class.current).to be_nil
    end

    it "returns the only household" do
      household = create(:household)
      expect(described_class.current).to eq(household)
    end

    it "returns the oldest household (lowest id) when several exist" do
      first  = create(:household)
      _second = create(:household)
      expect(described_class.current).to eq(first)
    end

    it "is computed fresh, not memoized at class level" do
      expect(described_class.current).to be_nil
      household = create(:household)
      expect(described_class.current).to eq(household)
    end
  end
end
