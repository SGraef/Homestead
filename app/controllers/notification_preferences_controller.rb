# frozen_string_literal: true
# typed: false

# The signed-in user's own notification settings: which proactive-reminder kinds
# they receive, and a quiet-hours window that suppresses push. Always scoped to
# current_user, so no household/Pundit gating is needed.
class NotificationPreferencesController < ApplicationController
  def show
    @preference = current_user.notification_preference
  end

  def update
    @preference = current_user.notification_preference
    @preference.disabled_kinds = Notification::REMINDER_KINDS - enabled_kinds
    @preference.quiet_hours_start = hour_param(:quiet_hours_start)
    @preference.quiet_hours_end   = hour_param(:quiet_hours_end)

    if @preference.save
      redirect_to notification_preference_path, notice: t("notification_preference.saved")
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  # Checked reminder kinds from the form, clamped to the known reminder set so a
  # forged param can't store an arbitrary kind.
  def enabled_kinds
    Array(params.dig(:notification_preference, :enabled_kinds)).map(&:to_s) &
      Notification::REMINDER_KINDS
  end

  # A blank hour means "no bound" (quiet hours off); otherwise 0-23.
  def hour_param(key)
    value = params.dig(:notification_preference, key)
    value.presence&.to_i
  end
end
