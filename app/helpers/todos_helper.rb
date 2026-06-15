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
end
