# frozen_string_literal: true
# typed: ignore

Rails.application.config.sorcery.submodules = %i[remember_me reset_password user_activation]

Rails.application.config.sorcery.configure do |config|
  config.user_config do |user|
    user.username_attribute_names      = [:email]
    user.password_attribute_name       = :password
    user.email_attribute_name          = :email
    user.crypted_password_attribute_name = :crypted_password
    user.salt_attribute_name           = :salt
    user.stretches                     = 12
    user.encryption_algorithm          = :bcrypt

    # Sorcery does NOT constantize these — it invokes `mailer.send(method, user)`
    # directly, so the value must be the actual class, not a string. Zeitwerk
    # autoloads `UserMailer` on first reference, so the bare constant is fine.
    user.user_activation_mailer              = UserMailer
    user.activation_needed_email_method_name = :activation_needed_email
    user.activation_success_email_method_name = :activation_success_email
    user.activation_token_attribute_name     = :activation_token
    user.activation_state_attribute_name     = :activation_state
    user.activation_mailer_disabled          = false
    user.activation_token_expires_at_attribute_name = :activation_token_expires_at

    user.reset_password_mailer               = UserMailer
    user.reset_password_email_method_name    = :reset_password_email
    user.reset_password_token_attribute_name = :reset_password_token
    user.reset_password_token_expires_at_attribute_name = :reset_password_token_expires_at
    user.reset_password_email_sent_at_attribute_name    = :reset_password_email_sent_at
    user.reset_password_time_between_emails = 5.minutes

    user.remember_me_token_attribute_name = :remember_me_token
    user.remember_me_token_expires_at_attribute_name = :remember_me_token_expires_at
  end

  config.user_class = "User"
end
