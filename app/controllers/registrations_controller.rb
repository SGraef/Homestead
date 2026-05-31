# frozen_string_literal: true
# typed: false

class RegistrationsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new
    @user = User.new
  end

  # On successful sign-up we leave the user in `activation_state: "pending"`;
  # the Sorcery `user_activation` submodule generates the token and mails it
  # via {UserMailer#activation_needed_email}. The household is created up
  # front so the very first sign-in after activation already has a tenancy.
  def create
    @user = User.new(user_params)

    if @user.save
      household = Household.create!(
        name: "#{@user.email.split("@").first.titleize} Haushalt"
      )
      Membership.create!(user: @user, household: household, role: "admin")

      redirect_to login_path, notice: t("auth.activation_email_sent")
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :name, :password, :password_confirmation)
  end
end
