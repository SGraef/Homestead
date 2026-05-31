# frozen_string_literal: true
# typed: false

# Handles the URL embedded in the activation email.
#
# Sorcery's `User.load_from_activation_token` looks up the user by token and
# returns nil for unknown / expired / already-activated states. On success
# we call `activate!`, which flips `activation_state` to "active" and (per
# the mailer config) sends the success email.
class ActivationsController < ApplicationController
  skip_before_action :require_login

  def show
    user = User.load_from_activation_token(params[:token])

    if user.nil?
      redirect_to login_path, alert: t("activation.invalid")
      return
    end

    user.activate!
    redirect_to login_path, notice: t("activation.success")
  end

  # POST /activations -- re-send the activation email if the user lost it.
  def create
    user = User.find_by(email: params[:email].to_s.downcase.strip)
    UserMailer.activation_needed_email(user).deliver_later if user&.activation_state == "pending"
    # Always show the same flash so we don't leak account existence.
    redirect_to login_path, notice: t("activation.resent")
  end
end
