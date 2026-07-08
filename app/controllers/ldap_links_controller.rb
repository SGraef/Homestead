# frozen_string_literal: true
# typed: false

# Self-service page where the signed-in user links ("syncs") their local
# account to an LDAP entry — or removes the link again. Linking requires
# proving ownership of the directory account: the entered username + password
# must survive an LDAP bind before the uid is stored on the user.
# Always scoped to current_user, so no Pundit gating is needed (same pattern
# as NotificationPreferencesController).
class LdapLinksController < ApplicationController
  before_action :set_connection

  def show; end

  def create
    return redirect_to(ldap_link_path, alert: t("ldap.link.not_configured")) unless @connection&.connected?

    entry = authenticate_against_directory
    if entry && current_user.update(ldap_uid: entry.uid)
      redirect_to ldap_link_path, notice: t("ldap.link.linked", uid: entry.uid)
    else
      # An LDAP transport error has already set its own alert; otherwise it is
      # either bad credentials or a model error (uid already linked elsewhere).
      flash.now[:alert] ||= entry ? current_user.errors.full_messages.to_sentence : t("ldap.link.failed")
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    current_user.update!(ldap_uid: nil)
    redirect_to ldap_link_path, notice: t("ldap.link.unlinked")
  end

  private

  def set_connection
    @connection = current_household&.ldap_connection
  end

  def authenticate_against_directory
    Ldap::Authenticator.new(@connection)
                       .authenticate(params[:ldap_username].to_s.strip, params[:ldap_password].to_s)
  rescue Ldap::Error => e
    flash.now[:alert] = t("ldap.link.error", error: e.message.to_s.first(300))
    nil
  end
end
