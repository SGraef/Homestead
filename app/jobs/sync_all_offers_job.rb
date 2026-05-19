# frozen_string_literal: true
# typed: true

# Fan-out: enqueue one {SyncOffersJob} per household that has a postcode
# configured. Called by Solid Queue's recurring scheduler (see
# config/recurring.yml) -- a single tick fans out, individual household
# jobs run on the default queue and don't block one another.
class SyncAllOffersJob < ApplicationJob
  queue_as :default

  def perform
    Household.where.not(postal_code: [nil, ""]).find_each do |h|
      SyncOffersJob.perform_later(h.id)
    end
  end
end
