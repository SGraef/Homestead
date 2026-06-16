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

  # Only manual events are scan-eligible for the event->todo direction; a
  # generated event (comment_extraction) is never re-scanned (loop guard).
  def task_like?
    return false unless source == "manual"

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

  # @return [Time] the end, defaulting to the start for a zero-length event.
  def effective_ends_at
    ends_at || starts_at
  end

  private

  def ends_after_starts
    return if ends_at.nil? || starts_at.nil?

    errors.add(:ends_at, :before_start) if ends_at < starts_at
  end
end
