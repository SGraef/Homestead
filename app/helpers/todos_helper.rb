# frozen_string_literal: true
# typed: false

module TodosHelper
  # State -> existing pill modifier (open: neutral, in_progress: warn, done: success).
  STATUS_PILL = {
    "open"        => "pill",
    "in_progress" => "pill warn",
    "done"        => "pill success"
  }.freeze

  def todo_status_badge(todo)
    content_tag(:span, t("todo.states.#{todo.status}"), class: STATUS_PILL.fetch(todo.status, "pill"))
  end

  # Display label for a household member (name falls back to email).
  def member_name(user)
    return "—" if user.nil?

    user.name.presence || user.email
  end

  # Actionable date suggestion for a comment, or nil. Suppressed once an event
  # exists for the comment or the suggestion was dismissed.
  def comment_date_suggestion(comment)
    suggestion = GermanDateExtractor.call(comment.body)
    return nil unless suggestion
    return nil if CalendarEvent.exists?(source_record: comment)
    return nil if comment.suggestion_dismissals.exists?(span_hash: suggestion.span_hash)

    suggestion
  end

  # True if a manual, task-like event hasn't already produced a todo (C7).
  def event_offers_todo?(event)
    event.task_like? && !Todo.exists?(source_calendar_event_id: event.id)
  end
end
