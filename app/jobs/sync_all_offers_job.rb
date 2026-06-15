# frozen_string_literal: true
# typed: true

# Recurring entry point (see config/recurring.yml): enqueue a {SyncOffersJob}
# for the single household if it has a postcode configured. Scoped to
# {Household.current} so a database upgraded from the old multi-household
# schema never pulls offers for orphaned households.
class SyncAllOffersJob < ApplicationJob
  queue_as :default

  def perform
    household = Household.current
    return if household.nil? || household.postal_code.to_s.strip.blank?

    SyncOffersJob.perform_later(household.id)
  end
end
