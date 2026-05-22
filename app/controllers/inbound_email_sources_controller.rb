# frozen_string_literal: true
# typed: false

# CRUD for the per-(user, household) IMAP mailboxes the inbound-
# receipts poller drains. Every household member can see what's been
# configured, but only the row's owner (the user who created it) can
# see the password field or edit/delete it.
class InboundEmailSourcesController < ApplicationController
  before_action :ensure_household
  before_action :load_source, only: %i[edit update destroy]
  before_action :require_owner!, only: %i[edit update destroy]

  def index
    @sources = current_household.inbound_email_sources.ordered.includes(:user)
  end

  def new
    @source = current_household.inbound_email_sources.build(
      user:      current_user,
      imap_port: 993,
      imap_ssl:  true,
      folder:    "INBOX"
    )
  end

  def create
    @source = current_household.inbound_email_sources.build(create_params)
    @source.user = current_user
    if @source.save
      redirect_to inbound_email_sources_path,
                  notice: t("inbound_email.created", label: @source.label)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @source.assign_attributes(update_params.except(:imap_password))
    @source.assign_password_if_present(params.dig(:inbound_email_source, :imap_password))
    if @source.save
      redirect_to inbound_email_sources_path,
                  notice: t("inbound_email.updated", label: @source.label)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    label = @source.label
    @source.destroy
    redirect_to inbound_email_sources_path,
                notice: t("inbound_email.deleted", label: label)
  end

  private

  def load_source
    @source = current_household.inbound_email_sources.find(params[:id])
  end

  def require_owner!
    return if @source.manageable_by?(current_user)

    redirect_to inbound_email_sources_path,
                alert: t("inbound_email.not_owner")
  end

  # The user picks every column here, including password.
  def create_params
    params.require(:inbound_email_source).permit(
      :label, :imap_host, :imap_port, :imap_ssl,
      :imap_username, :imap_password, :folder, :expunge
    )
  end

  # On update we let the form NOT resubmit the password (leaving the
  # field blank keeps the stored one). We strip :imap_password out of
  # the normal assign_attributes path; controller code calls
  # `assign_password_if_present` separately.
  def update_params
    params.require(:inbound_email_source).permit(
      :label, :imap_host, :imap_port, :imap_ssl,
      :imap_username, :imap_password, :folder, :expunge
    )
  end

  def ensure_household
    redirect_to new_household_path, alert: t("flash.create_household_first") unless current_household
  end
end
