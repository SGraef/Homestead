# frozen_string_literal: true

# VAPID configuration for Web Push. In production, set VAPID_PUBLIC_KEY /
# VAPID_PRIVATE_KEY (generate once with `WebPush.generate_key`) and VAPID_SUBJECT
# (a mailto: or https: contact). Rotating the keys invalidates every existing
# subscription (clients must re-subscribe). When unset outside production we
# generate an ephemeral pair so local/dev/test work without configuration; push
# is simply disabled in production if no keys are provided.
Rails.application.config.x.vapid = {
  subject:     ENV.fetch("VAPID_SUBJECT", "mailto:admin@pantria.local"),
  public_key:  ENV["VAPID_PUBLIC_KEY"].presence,
  private_key: ENV["VAPID_PRIVATE_KEY"].presence
}

if Rails.application.config.x.vapid[:public_key].blank? && !Rails.env.production?
  key = WebPush.generate_key
  Rails.application.config.x.vapid[:public_key]  = key.public_key
  Rails.application.config.x.vapid[:private_key] = key.private_key
end
