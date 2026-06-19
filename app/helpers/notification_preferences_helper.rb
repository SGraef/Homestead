# frozen_string_literal: true
# typed: false

module NotificationPreferencesHelper
  # [label, value] pairs for the quiet-hours hour selects (00:00 .. 23:00).
  def hour_options
    (0..23).map { |h| [format("%02d:00", h), h] }
  end
end
