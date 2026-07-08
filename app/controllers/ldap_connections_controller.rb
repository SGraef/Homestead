# frozen_string_literal: true
# typed: false

# Connect / edit / disconnect flow for the household's LDAP directory.
# Admin-only (see {LdapConnectionPolicy}). The service-account bind password
# is stored encrypted; the form never echoes it back.
class LdapConnectionsController < ApplicationController
  before_action :ensure_household
  before_action :set_connection, only: %i[show update destroy test]
  before_action :authorize_connection

  def show
    redirect_to(new_ldap_connection_path) unless @connection
  end

  def new
    @connection = current_household.ldap_connection || current_household.build_ldap_connection
  end

  def create
    @connection = current_household.ldap_connection || current_household.build_ldap_connection
    @connection.assign_attributes(connection_params)

    if @connection.save
      redirect_to ldap_connection_path, notice: t("ldap.saved")
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    return redirect_to(new_ldap_connection_path) unless @connection

    # Leave the stored password untouched when the field is submitted blank,
    # so an admin can tweak settings without re-entering the secret.
    attrs = connection_params
    attrs = attrs.except(:bind_password) if attrs[:bind_password].blank?

    if @connection.update(attrs)
      redirect_to ldap_connection_path, notice: t("ldap.saved")
    else
      render :show, status: :unprocessable_content
    end
  end

  # Users keep their ldap_uid on disconnect: the links go inert (logins fall
  # back to the local password) and come back to life if LDAP is reconnected.
  def destroy
    @connection&.destroy
    redirect_to ldap_connection_path, notice: t("ldap.disconnected")
  end

  # POST /ldap_connection/test — service bind + base-DN lookup.
  def test
    return redirect_to(new_ldap_connection_path) unless @connection&.connected?

    Ldap::Authenticator.new(@connection).test!
    @connection.update_columns(last_error: nil, updated_at: Time.current)
    redirect_to ldap_connection_path, notice: t("ldap.test_ok")
  rescue Ldap::Error => e
    @connection.update_columns(last_error: e.message.to_s.first(1000), updated_at: Time.current)
    redirect_to ldap_connection_path, alert: t("ldap.test_failed", error: e.message.to_s.first(300))
  end

  private

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_connection
    @connection = current_household.ldap_connection
  end

  def authorize_connection
    authorize(@connection || LdapConnection.new(household: current_household))
  end

  def connection_params
    params.require(:ldap_connection)
          .permit(:host, :port, :encryption, :base_dn, :bind_dn, :bind_password,
                  :uid_attribute, :user_filter, :verify_tls)
  end
end
