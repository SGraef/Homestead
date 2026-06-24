# frozen_string_literal: true
# typed: false

# Connect / edit / disconnect flow for a household's paperless-ngx instance.
# Admin-only (see {PaperlessConnectionPolicy}). The API token is stored
# encrypted; the form never echoes it back.
class PaperlessConnectionsController < ApplicationController
  before_action :ensure_household
  before_action :set_connection, only: %i[show update destroy test]
  before_action :authorize_connection

  def show
    redirect_to(new_paperless_connection_path) unless @connection
  end

  def new
    @connection = current_household.paperless_connection || current_household.build_paperless_connection
  end

  def create
    @connection = current_household.paperless_connection || current_household.build_paperless_connection
    @connection.assign_attributes(connection_params)

    if @connection.save
      redirect_to paperless_connection_path, notice: t("paperless.saved")
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    return redirect_to(new_paperless_connection_path) unless @connection

    # Leave the stored token untouched when the field is submitted blank, so an
    # admin can tweak the URL / tags without re-entering the secret.
    attrs = connection_params
    attrs = attrs.except(:api_token) if attrs[:api_token].blank?

    if @connection.update(attrs)
      redirect_to paperless_connection_path, notice: t("paperless.saved")
    else
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    @connection&.destroy
    redirect_to paperless_connection_path, notice: t("paperless.disconnected")
  end

  # POST /paperless_connection/test -- verify the URL + token reach a paperless API.
  def test
    return redirect_to(new_paperless_connection_path) unless @connection&.connected?

    Paperless::Client.new(@connection).ping
    @connection.update_columns(last_error: nil, updated_at: Time.current)
    redirect_to paperless_connection_path, notice: t("paperless.test_ok")
  rescue Paperless::Error => e
    @connection.update_columns(last_error: e.message.to_s.first(1000), updated_at: Time.current)
    redirect_to paperless_connection_path, alert: t("paperless.test_failed", error: e.message.to_s.first(300))
  end

  private

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_connection
    @connection = current_household.paperless_connection
  end

  def authorize_connection
    authorize(@connection || PaperlessConnection.new(household: current_household))
  end

  def connection_params
    params.require(:paperless_connection)
          .permit(:base_url, :api_token, :verify_ssl, :default_tags)
  end
end
