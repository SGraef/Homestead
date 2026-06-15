# frozen_string_literal: true
# typed: false

# Connect / pick-list / disconnect flow for Bring!. Login happens server-side
# (the user's password is exchanged for tokens immediately and never stored)
# then a list-picker step lets them pick which Bring! list Pantria should
# push to.
class BringConnectionsController < ApplicationController
  before_action :ensure_household
  before_action :authorize_admin!

  def show
    @connection = current_household.bring_connection
    return redirect_to(new_bring_connection_path) unless @connection

    # Only hit `/lists` when the user explicitly asks (?reload=1) -- a
    # transient blip on this single endpoint must not poison the just-issued
    # token. Otherwise we render the dropdown using whatever was last picked.
    return unless @connection.access_token.present? && params[:reload].present?

    @lists = safe_fetch_lists(@connection)
  end

  def new
    @connection = current_household.bring_connection || current_household.build_bring_connection
  end

  def create
    auth = Bring::Client.login(
      email:    params.dig(:bring_connection, :email).to_s.strip,
      password: params.dig(:bring_connection, :password).to_s,
      country:  params.dig(:bring_connection, :country_code).presence || "DE"
    )

    connection = current_household.bring_connection || current_household.build_bring_connection
    connection.assign_attributes(
      bring_email:             auth["email"].presence || params.dig(:bring_connection, :email),
      bring_user_uuid:         auth["uuid"],
      default_list_uuid:       auth["bringListUUID"],
      access_token:            auth["access_token"],
      refresh_token:           auth["refresh_token"],
      token_type:              auth["token_type"].presence || "Bearer",
      access_token_expires_at: Time.current + auth.fetch("expires_in", 3600).to_i.seconds,
      country_code:            (params.dig(:bring_connection, :country_code).presence || "DE").upcase,
      last_error:              nil
    )
    connection.save!

    # Try to fetch lists once with the fresh token. If Bring rejects it we
    # KEEP the saved connection (with the error landing in last_error) so the
    # user can retry from the show page or read the diagnostics, rather than
    # being bounced back to a blank connect form.
    begin
      @lists = Bring::Client.new(connection).lists
      redirect_to bring_connection_path, notice: t("bring.connected")
    rescue Bring::AuthError, Bring::Error => e
      redirect_to bring_connection_path,
                  alert: t("bring.login_failed", error: e.message.to_s.first(300))
    end
  rescue Bring::AuthError => e
    # Reached only when the initial /bringauth login itself failed.
    flash.now[:alert] = t("bring.login_failed", error: e.message)
    @connection = current_household.build_bring_connection(bring_email: params.dig(:bring_connection, :email))
    render :new, status: :unprocessable_content
  end

  def update
    @connection = current_household.bring_connection
    return redirect_to(new_bring_connection_path) unless @connection

    list_uuid = params.dig(:bring_connection, :default_list_uuid)
    list_name = params.dig(:bring_connection, :default_list_name)
    @connection.update!(default_list_uuid: list_uuid.presence,
                        default_list_name: list_name.presence)
    redirect_to bring_connection_path, notice: t("bring.list_updated")
  end

  def destroy
    current_household.bring_connection&.destroy
    redirect_to root_path, notice: t("bring.disconnected")
  end

  # POST /bring_connection/sync — pull the latest Bring! list state into
  # Pantria right now, on top of the periodic scheduled pull.
  def sync
    connection = current_household.bring_connection
    return redirect_to(new_bring_connection_path) unless connection&.connected?

    outcome = Bring::Pull.new(connection).call
    redirect_to bring_connection_path,
                notice: t("bring.synced",
                          added:            outcome.added,
                          reactivated:      outcome.reactivated,
                          marked_purchased: outcome.marked_purchased)
  rescue Bring::Error => e
    redirect_to bring_connection_path, alert: t("bring.sync_failed", error: e.message)
  end

  private

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end

  def authorize_admin!
    return if current_user.admin_of?(current_household)

    redirect_to root_path, alert: t("flash.not_authorized")
  end

  def safe_fetch_lists(connection)
    Bring::Client.new(connection).lists
  rescue Bring::Error => e
    @list_error = e.message
    []
  end
end
