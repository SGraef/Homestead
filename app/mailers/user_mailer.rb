# frozen_string_literal: true
# typed: true

# Account-lifecycle mailer Sorcery hooks into.
#
# Sorcery dispatches messages by class + method name; the names below match
# the defaults in `config/initializers/sorcery.rb`:
#
#   - {#activation_needed_email}  sent on user create   (user_activation)
#   - {#activation_success_email} sent after activation (user_activation)
#   - {#reset_password_email}     sent on reset request (reset_password)
class UserMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM", "no-reply@pantria.local")

  # @param user [User]
  def activation_needed_email(user)
    @user  = user
    @url   = activation_url(token: user.activation_token, host: mail_host, port: mail_port)
    mail to: user.email, subject: t("user_mailer.activation_needed_email.subject")
  end

  # @param user [User]
  def activation_success_email(user)
    @user = user
    @url  = login_url(host: mail_host, port: mail_port)
    mail to: user.email, subject: t("user_mailer.activation_success_email.subject")
  end

  # @param user [User]
  def reset_password_email(user)
    @user = user
    @url  = edit_password_reset_url(token: user.reset_password_token, host: mail_host, port: mail_port)
    mail to: user.email, subject: t("user_mailer.reset_password_email.subject")
  end

  private

  # `default_url_options[:host]` is set per env in `config/environments/*.rb`,
  # but the mailer can also be invoked from a job context where Rails has no
  # request to derive the host from -- read from the same env var the prod
  # config uses to keep links correct.
  def mail_host
    ENV.fetch("APP_HOST", Rails.application.config.action_mailer.default_url_options[:host] || "localhost")
  end

  def mail_port
    Rails.application.config.action_mailer.default_url_options[:port]
  end
end
