# frozen_string_literal: true
# typed: ignore

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("ALLOWED_API_ORIGINS", "*").split(",")

    resource "/api/*",
             headers:     :any,
             methods:     %i[get post put patch delete options head],
             expose:      %w[Authorization X-Total-Count],
             credentials: false
  end
end
