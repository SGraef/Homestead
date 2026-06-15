# frozen_string_literal: true
# typed: false

class RegistrationsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]
  before_action :require_first_run, only: %i[new create]

  def new
    @user = User.new
  end

  # On successful sign-up we leave the user in `activation_state: "pending"`;
  # the Sorcery `user_activation` submodule generates the token and mails it
  # via {UserMailer#activation_needed_email}. This is the FIRST-RUN bootstrap:
  # the single household is created here, and the first user becomes its admin.
  # After this, self-registration is closed -- admins add further members by
  # email from the household settings page.
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

  # Self-registration is only open on a brand-new, empty instance. Once the
  # single household (or any user) exists, the sign-up surface is closed and
  # new members are added by an admin instead.
  def require_first_run
    return if Household.current.nil? && User.none?

    redirect_to login_path, alert: t("auth.registration_closed")
  end

  def user_params
    params.require(:user).permit(:email, :name, :password, :password_confirmation)
  end
end
