# frozen_string_literal: true
# typed: false

# Extracts a payment due date from a non-receipt {Document} and creates (or
# updates) a reminder {Todo} so the bill shows up on the household calendar.
#
#   OCR text  →  Documents::DueDateExtractor  →  due_on  →  reminder Todo
#
# Rules:
#   * Receipts are skipped entirely -- a completed purchase has no due date.
#   * A detectable due date is used as-is.
#   * No detectable date (incl. unreadable OCR) falls back to +1 week, so every
#     bill still gets a reminder.
#
# Idempotent: re-running updates the one reminder todo linked to the document
# (matched on source_document_id) rather than spawning duplicates, and never
# clobbers a status the household already advanced.
class ProcessDocumentJob < ApplicationJob
  FALLBACK_DAYS = 7

  # OCR is CPU-bound; share the capped `receipts` queue with ProcessReceiptJob
  # so a batch of uploads can't pin every core.
  queue_as :receipts

  discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

  # @param document_id [Integer]
  def perform(document_id)
    document = Document.find(document_id)
    return if document.receipt? || !document.file.attached?

    reference = household_today(document.household)
    detected  = Documents::DueDateExtractor.call(extract_text(document), reference: reference)
    due_on    = detected || (reference + FALLBACK_DAYS)

    document.update!(due_on: due_on, due_on_detected: detected.present?)
    upsert_reminder(document, due_on)
  end

  private

  def extract_text(document)
    document.file.open do |file|
      ReceiptScanner.adapter.extract_text(file.path)
    end
  rescue StandardError => e
    # A bill with unreadable OCR should still get a fallback reminder, so we
    # swallow extraction failures and proceed with empty text.
    Rails.logger.warn("[ProcessDocumentJob] OCR failed for document #{document.id}: #{e.class}: #{e.message}")
    ""
  end

  def upsert_reminder(document, due_on)
    todo = document.household.todos.find_or_initialize_by(source_document_id: document.id)
    todo.title    = reminder_title(document)
    todo.due_on   = due_on
    todo.source   = "document"
    todo.creator ||= document.user
    todo.save!
  end

  def reminder_title(document)
    I18n.t("document.payment_todo_title", title: document.title)
  end

  # "Today" in the household's timezone, so the +1-week fallback and year
  # inference line up with how the calendar buckets dates.
  def household_today(household)
    Time.find_zone(household.timezone.to_s)&.today || Date.current
  end
end
