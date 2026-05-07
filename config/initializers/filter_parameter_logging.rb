# frozen_string_literal: true
# typed: ignore

Rails.application.config.filter_parameters += %i[
  password password_confirmation crypted_password salt
  reset_password_token remember_me_token activation_token api_token
]
