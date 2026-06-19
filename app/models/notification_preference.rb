# frozen_string_literal: true
# typed: false

# One row per user holding their notification settings: which proactive-reminder
# kinds they've opted out of, and a quiet-hours window during which push is
# suppressed (the in-app bell still records everything). Read via
# {User#notification_preference}, which returns a sensible default when no row
# exists yet — so callers never nil-check.
class NotificationPreference < ApplicationRecord
  belongs_to :user

  validates :quiet_hours_start, :quiet_hours_end,
            numericality: { only_integer: true,
                            greater_than_or_equal_to: 0, less_than_or_equal_to: 23 },
            allow_nil: true

  # @param kind [String, Symbol] a {Notification} kind
  # @return [Boolean] true unless the user has opted out of this kind.
  def allows?(kind)
    Array(disabled_kinds).exclude?(kind.to_s)
  end

  # @param hour [Integer] 0-23, the recipient's current local hour
  # @return [Boolean] whether `hour` falls inside the quiet-hours window.
  #   Windows may wrap past midnight (e.g. 22 → 7). Returns false when quiet
  #   hours aren't set or the window is empty.
  def quiet_at?(hour)
    s = quiet_hours_start
    e = quiet_hours_end
    return false if s.nil? || e.nil? || s == e

    s < e ? (hour >= s && hour < e) : (hour >= s || hour < e)
  end
end
