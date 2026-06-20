# frozen_string_literal: true
# typed: false

# Pushes one {Document} into the household's paperless-ngx instance and mirrors
# the classifier's output back onto the row.
#
# paperless consumes uploads asynchronously, so this runs in two phases across
# re-enqueues:
#
#   1. upload — POST the file, store the returned Celery task UUID, status
#               flips to "pending".
#   2. poll   — re-enqueued every {POLL_WAIT}; once the task reports SUCCESS we
#               read the consumed document, resolve its type/correspondent/tag
#               *names*, best-effort match them onto a household OfferCategory
#               (via {OfferCategorizer}), and flip to "synced".
#
# The whole job is a no-op when no {PaperlessConnection} is configured -- the
# document just stays a local archive entry.
class PaperlessPushJob < ApplicationJob
  MAX_POLLS = 10
  POLL_WAIT = 15.seconds

  queue_as :default

  discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

  # @param document_id [Integer]
  # @param poll [Integer] poll attempt counter (0 = upload phase)
  def perform(document_id, poll: 0)
    document = Document.find(document_id)
    connection = document.household.paperless_connection
    return unless connection&.connected?
    return if document.paperless_linked? # already synced; nothing to do

    client = Paperless::Client.new(connection)
    if document.paperless_task_uuid.blank?
      start_upload(document, connection, client)
    else
      poll_task(document, connection, client, poll)
    end
  rescue Paperless::Error => e
    record_failure(document_id, connection, e.message)
  end

  private

  def start_upload(document, connection, client)
    uuid = document.file.open do |file|
      client.upload(
        io:       file,
        filename: upload_filename(document),
        title:    document.title,
        tags:     connection.default_tags_list
      )
    end
    document.update!(status: "pending", paperless_task_uuid: uuid, error_message: nil)
    self.class.set(wait: POLL_WAIT).perform_later(document.id, poll: 1)
  end

  def poll_task(document, connection, client, poll)
    task = client.task(document.paperless_task_uuid)
    case task && task["status"]
    when "SUCCESS"
      finalize(document, connection, client, task["related_document"])
    when "FAILURE"
      document.update!(status:        "failed",
                       error_message: (task["result"] || "paperless consumption failed").to_s.first(1000))
    else
      requeue_or_timeout(document, poll)
    end
  end

  def requeue_or_timeout(document, poll)
    if poll >= MAX_POLLS
      document.update!(status: "failed", error_message: "paperless did not finish consuming in time")
    else
      self.class.set(wait: POLL_WAIT).perform_later(document.id, poll: poll + 1)
    end
  end

  def finalize(document, connection, client, doc_id)
    if doc_id.blank?
      # Consumed but no id returned -- paperless does this when it recognises a
      # duplicate. We can't build a deep link without an id, so flag it.
      document.update!(status:        "failed",
                       error_message: "paperless returned no document id (possible duplicate)")
      return
    end

    detail = client.document(doc_id)
    type = client.document_type_name(detail["document_type"])
    correspondent = client.correspondent_name(detail["correspondent"])
    tags = Array(detail["tags"]).filter_map { |tid| client.tag_name(tid) }

    document.update!(
      status:                  "synced",
      paperless_document_id:   doc_id,
      paperless_synced_at:     Time.current,
      paperless_document_type: type,
      paperless_correspondent: correspondent,
      paperless_tags:          tags.join(", "),
      matched_category:        match_category(document.household, type, correspondent, tags),
      error_message:           nil
    )
    connection.update_columns(last_synced_at: Time.current, last_error: nil, updated_at: Time.current)
  end

  # Best-effort: feed the paperless classification into the household's own
  # keyword categorizer. Returns nil (-> "uncategorised") when nothing matches.
  def match_category(household, type, correspondent, tags)
    needle = [type, correspondent, *tags].compact_blank.join(" ")
    return nil if needle.strip.empty?

    OfferCategorizer.classify(needle, household: household)
  end

  # paperless keys documents partly on the uploaded filename, so give it the
  # real attachment name (falling back to the blob's).
  def upload_filename(document)
    document.file.filename.to_s.presence || "document-#{document.id}"
  end

  def record_failure(document_id, connection, message)
    Document.where(id: document_id).update_all(
      status:        "failed",
      error_message: message.to_s.first(1000),
      updated_at:    Time.current
    )
    connection&.update_columns(last_error: message.to_s.first(1000), updated_at: Time.current)
  end
end
