# frozen_string_literal: true
# typed: false

# Delivers one {Notification} to every Web Push subscription of its recipient.
# A 410/404 from the push service means the subscription is dead — prune it so
# the job never retry-storms a gone endpoint. Other errors are logged, not
# fatal, so one bad endpoint doesn't abort the fan-out.
class DeliverPushJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

  def perform(notification_id)
    notification = Notification.find(notification_id)
    return if quiet_hours?(notification) # bell still has it; just don't ping now

    vapid = Rails.application.config.x.vapid
    return if vapid[:public_key].blank? || vapid[:private_key].blank?

    payload = {
      title: notification.title,
      body:  notification.body,
      url:   notification.url.presence || "/",
      tag:   "notification-#{notification.id}"
    }.to_json

    notification.user.push_subscriptions.find_each { |sub| deliver_to(sub, payload, vapid) }
  end

  private

  # Suppress push during the recipient's quiet hours (evaluated in the
  # household's timezone). The in-app bell already recorded the notification.
  def quiet_hours?(notification)
    zone = ActiveSupport::TimeZone[notification.household.timezone.to_s] || Time.zone
    notification.user.notification_preference.quiet_at?(zone.now.hour)
  end

  def deliver_to(sub, payload, vapid)
    WebPush.payload_send(
      message:  payload,
      endpoint: sub.endpoint,
      p256dh:   sub.p256dh,
      auth:     sub.auth,
      vapid:    { subject: vapid[:subject], public_key: vapid[:public_key], private_key: vapid[:private_key] }
    )
    sub.update_column(:last_used_at, Time.current)
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    sub.destroy # 410 Gone / 404 Not Found -> dead endpoint, prune it
  rescue WebPush::ResponseError => e
    Rails.logger.warn("[push] delivery failed for subscription ##{sub.id}: #{e.class}")
  end
end
