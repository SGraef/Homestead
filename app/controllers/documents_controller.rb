# frozen_string_literal: true
# typed: false

# CRUD for the household document archive (receipts, bills, invoices...). The
# file is stored locally via Active Storage; when a {PaperlessConnection} is
# configured, creating a document also enqueues {PaperlessPushJob} to mirror it
# into paperless-ngx and pull the classification back.
class DocumentsController < ApplicationController
  before_action :ensure_household
  before_action :set_document, only: %i[show destroy sync]

  def index
    @documents = policy_scope(current_household.documents).recent.limit(100)
    @connection = current_household.paperless_connection
  end

  def show
    authorize @document
    @connection = current_household.paperless_connection
    @reminder_todo = @document.reminder_todos.first
  end

  def new
    @document = current_household.documents.build
    authorize @document
  end

  def create
    @document = current_household.documents.build(create_params.merge(user: current_user))
    @document.file.attach(params.dig(:document, :file))
    authorize @document

    if @document.save
      maybe_push(@document)
      # Non-receipt documents get OCR'd for a payment due date + reminder todo.
      ProcessDocumentJob.perform_later(@document.id) unless @document.receipt?
      redirect_to @document, notice: t("notices.document_uploaded")
    else
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    authorize @document
    @document.destroy
    redirect_to documents_path, notice: t("notices.document_removed")
  end

  # POST /documents/:id/sync -- (re)push to paperless. Only meaningful when a
  # connection exists and the document isn't already linked.
  def sync
    authorize @document, :update?
    connection = current_household.paperless_connection
    return redirect_to(@document, alert: t("notices.document_paperless_unconfigured")) unless connection&.connected?
    return redirect_to(@document, alert: t("notices.document_already_synced")) if @document.paperless_linked?

    @document.update(status: "pending", paperless_task_uuid: nil, error_message: nil)
    PaperlessPushJob.perform_later(@document.id)
    redirect_to @document, notice: t("notices.document_sync_started")
  end

  private

  def ensure_household
    redirect_to root_path, alert: t("flash.create_household_first") unless current_household
  end

  def set_document
    @document = current_household.documents.find(params[:id])
  end

  def create_params
    params.require(:document).permit(:title, :note, :kind)
  end

  # Only reach out to paperless when it's actually configured -- otherwise the
  # document stays a local-only archive entry (status "stored").
  def maybe_push(document)
    return unless current_household.paperless_connection&.connected?

    document.update_columns(status: "pending", updated_at: Time.current)
    PaperlessPushJob.perform_later(document.id)
  end
end
