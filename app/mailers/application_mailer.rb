# frozen_string_literal: true
# typed: true

class ApplicationMailer < ActionMailer::Base
  default from: "no-reply@pantria.local"
  layout "mailer"
end
