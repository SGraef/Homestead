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
    @calendars = @connection.linked? ? load_calendars : []
  end

  def update
    authorize @connection
    if @connection.update(connection_params)
      redirect_to calendar_connection_path, notice: t("notices.calendar_connection_saved")
    else
      render :show, status: :unprocessable_content
    end
  end

  # POST /calendar_connection/connect — start the Google OAuth consent flow.
  def connect
    authorize @connection, :update?
    return redirect_to(calendar_connection_path, alert: t("calendar_connection.not_configured")) unless @connection.configured?

    @connection.save! if @connection.new_record?
    state = SecureRandom.urlsafe_base64(24)
    session[:google_oauth_state] = state
    redirect_to CalendarSync::Google::Oauth.authorize_url(@connection, redirect_uri: callback_url, state: state),
                allow_other_host: true
  end

  # GET /calendar_connection/callback — Google redirects here after consent.
  def callback
    authorize @connection, :update?
    expected = session.delete(:google_oauth_state)
    if params[:error].present? || params[:state].blank? || params[:state] != expected
      return redirect_to(calendar_connection_path, alert: t("calendar_connection.connect_failed"))
    end

    CalendarSync::Google::Oauth.exchange_code(@connection, code: params[:code], redirect_uri: callback_url)
    redirect_to calendar_connection_path, notice: t("calendar_connection.connected_notice")
  rescue CalendarSync::Google::Error
    @connection.update(status: "error", last_error_code: "oauth")
    redirect_to calendar_connection_path, alert: t("calendar_connection.connect_failed")
  end

  # PATCH /calendar_connection/select_calendar — pick which Google calendar to sync.
  def select_calendar
    authorize @connection, :update?
    @connection.update!(calendar_id: params[:calendar_id])
    redirect_to calendar_connection_path, notice: t("calendar_connection.calendar_selected")
  end

  # POST /calendar_connection/sync — trigger a pull now (instead of waiting for the poll).
  def sync
    authorize @connection, :update?
    CalendarPollJob.perform_later if @connection.connected? && @connection.calendar_id.present?
    redirect_to calendar_connection_path, notice: t("calendar_connection.sync_started")
  end

  # DELETE /calendar_connection/disconnect — clear tokens + sync state.
  def disconnect
    authorize @connection, :update?
    @connection.update!(access_token: nil, refresh_token: nil, token_expires_at: nil,
                        sync_token: nil, calendar_id: nil, status: "disconnected", last_error_code: nil)
    redirect_to calendar_connection_path, notice: t("calendar_connection.disconnected_notice")
  end

  private

  def callback_url
    callback_calendar_connection_url
  end

  def load_calendars
    calendars = CalendarSync::Google::ApiClient.new(@connection).list_calendars
    @connection.update!(status: "connected", last_error_code: nil) unless @connection.connected?
    calendars
  rescue CalendarSync::Google::Error
    @connection.update(status: "error", last_error_code: "api")
    []
  end

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
