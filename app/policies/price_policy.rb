# frozen_string_literal: true
# typed: true

class PricePolicy < ApplicationPolicy
  protected

  def household_for(record)
    record.product&.household
  end
end
