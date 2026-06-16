# frozen_string_literal: true
# typed: false

# Receives PushManager subscriptions from the browser (push_subscribe Stimulus
# controller POSTs subscription.toJSON()). Upserts on the endpoint digest.
class PushSubscriptionsController < ApplicationController
  # CSRF protection stays ON (inherited from ApplicationController). The
  # push_subscribe Stimulus controller already sends the Rails authenticity
  # token in the `X-CSRF-Token` header it reads from the <meta> tag, so the
  # JSON fetch verifies like any other state-changing request — no skip needed.

  def create
    endpoint = params[:endpoint].to_s
    p256dh   = params.dig(:keys, :p256dh).to_s
    auth     = params.dig(:keys, :auth).to_s
    return head(:unprocessable_content) if endpoint.blank? || p256dh.blank? || auth.blank?

    sub = PushSubscription.find_or_initialize_by(endpoint_digest: PushSubscription.digest_for(endpoint))
    sub.assign_attributes(
      user: current_user, household: current_household,
      endpoint: endpoint, p256dh: p256dh, auth: auth,
      user_agent: request.user_agent, last_used_at: Time.current
    )
    sub.save!
    head :created
  end

  def destroy
    endpoint = params[:endpoint].to_s
    if endpoint.present?
      current_user.push_subscriptions
                  .where(endpoint_digest: PushSubscription.digest_for(endpoint))
                  .destroy_all
    end
    head :no_content
  end
end
