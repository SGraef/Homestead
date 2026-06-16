# frozen_string_literal: true
# typed: false

# Runs the action (and its view rendering) in the household's timezone so that
# datetime fields display and parse in local wall-clock time, while the DB keeps
# UTC. Scoped to calendar controllers — not applied globally.
module HouseholdTimeZone
  extend ActiveSupport::Concern

  included do
    around_action :use_household_time_zone
  end

  private

  def use_household_time_zone(&block)
    tz = current_household&.timezone.presence || Time.zone
    Time.use_zone(tz, &block)
  end
end
