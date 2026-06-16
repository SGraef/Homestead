# frozen_string_literal: true
# typed: false

# A calendar event owned by the single household. Times are stored UTC and
# rendered in Household.current.timezone. `source` is the provenance gate for
# the keyword loop (a non-"manual" event is never re-scanned).
class CalendarEvent < ApplicationRecord
  SOURCES = %w[manual comment_extraction todo].freeze
  # Keywords that make a manually-created event "task-like" (offers a todo, C7).
  TASK_TRIGGERS = %w[aufgabe todo erledigen besorgen kaufen anrufen mitbringen abgeben].freeze

  belongs_to :household
  belongs_to :source_record, polymorphic: true, optional: true
  belongs_to :calendar_connection, optional: true

  # Only locally-authored manual events are scan-eligible for the event->todo
  # direction. A generated event (comment_extraction) OR a pulled remote event
  # (sync_origin == "remote") is never re-scanned — otherwise a first calendar
  # sync would spawn a wall of unsolicited todo suggestions (loop guard).
  def task_like?
    return false unless source == "manual" && sync_origin == "local"

    down = title.to_s.downcase
    TASK_TRIGGERS.any? { |k| down.include?(k) }
  end

  validates :title, presence: true, length: { maximum: 200 }
  validates :starts_at, presence: true
  validates :source, inclusion: { in: SOURCES }
  validate  :ends_after_starts

  scope :manual, -> { where(source: "manual") }
  # Events whose start falls within a [from, to] datetime window.
  scope :starting_between, ->(from, to) { where(starts_at: from..to) }

  # Local events created while a calendar is connected auto-attach so they push.
  before_create :attach_connection, if: -> { sync_origin == "local" && calendar_connection_id.nil? }

  # Push local changes to the remote calendar (skipped while applying a pull —
  # the echo guard — and never for remote-origin / recurring events).
  after_create_commit  :enqueue_push_create
  after_update_commit  :enqueue_push_update
  after_destroy_commit :enqueue_push_delete

  # Echo guard (mirrors GroceryItem.without_bring_sync): writes applied FROM a
  # remote pull are wrapped in this block so the push-back hooks (PR4) don't
  # re-send them to the server.
  def self.without_sync
    prev = Thread.current[:pantria_skip_calendar_sync]
    Thread.current[:pantria_skip_calendar_sync] = true
    yield
  ensure
    Thread.current[:pantria_skip_calendar_sync] = prev
  end

  def self.skip_sync?
    Thread.current[:pantria_skip_calendar_sync] == true
  end

  # Locally-authored, non-recurring, on a connected calendar -> eligible to push.
  def pushable?
    sync_origin == "local" && !recurring && calendar_connection&.connected? &&
      calendar_connection.calendar_id.present?
  end

  # @return [Time] the end, defaulting to the start for a zero-length event.
  def effective_ends_at
    ends_at || starts_at
  end

  private

  def ends_after_starts
    return if ends_at.nil? || starts_at.nil?

    errors.add(:ends_at, :before_start) if ends_at < starts_at
  end

  def attach_connection
    connection = household&.calendar_connection
    self.calendar_connection = connection if connection&.connected? && connection.calendar_id.present?
  end

  def enqueue_push_create
    return if self.class.skip_sync? || !pushable?

    CalendarPushJob.perform_later("create", event_id: id)
  end

  def enqueue_push_update
    return if self.class.skip_sync?
    return unless sync_origin == "local" && remote_id.present? && calendar_connection&.connected?

    CalendarPushJob.perform_later("update", event_id: id)
  end

  def enqueue_push_delete
    return if self.class.skip_sync?
    return unless remote_id.present? && calendar_connection_id.present?

    CalendarPushJob.perform_later("delete", connection_id: calendar_connection_id,
                                            calendar_id: calendar_connection&.calendar_id,
                                            remote_id: remote_id, etag: etag)
  end
end
