# frozen_string_literal: true
# typed: false

# The in-app notification bell/list. Strictly scoped to the current user's own
# notifications (notifications are per-recipient, not household-shared).
class NotificationsController < ApplicationController
  def index
    @notifications = current_user.notifications.recent.limit(100)
  end

  # POST /notifications/:id/read — mark one read and follow its deep link.
  def read
    notification = current_user.notifications.find(params[:id])
    notification.mark_read!
    redirect_to(notification.url.presence || notifications_path)
  end

  # POST /notifications/read_all
  def read_all
    current_user.notifications.unread.update_all(read_at: Time.current)
    redirect_to notifications_path, notice: t("notification.all_read")
  end
end
