# frozen_string_literal: true
# typed: false

# Admin-only settings for the household's external-calendar connection. PR1:
# save the Google OAuth client credentials + show status. The OAuth connect flow
# and sync land in later PRs.
class CalendarConnectionsController < ApplicationController
  before_action :ensure_household
  before_action :set_connection

  def show
    authorize @connection
  end

  def update
    authorize @connection
    if @connection.update(connection_params)
      redirect_to calendar_connection_path, notice: t("notices.calendar_connection_saved")
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_connection
    @connection = current_household.calendar_connection ||
                  current_household.build_calendar_connection(provider: "google")
  end

  def connection_params
    permitted = params.require(:calendar_connection).permit(:client_id, :client_secret, :calendar_id)
    # Blank means "keep the stored secret" (the field is never pre-filled).
    permitted.delete(:client_secret) if permitted[:client_secret].blank?
    permitted
  end

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end
end
