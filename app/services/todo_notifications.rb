# frozen_string_literal: true
# typed: false

# Creates in-app {Notification} rows for todo events. Controllers call these
# after a successful change, passing the acting user so the actor never notifies
# themselves. Push delivery is layered on in a later phase; for now these rows
# surface in the nav bell. Idempotent via Notification#deliver's dedup_key.
class TodoNotifications
  class << self
    # Assignee changed -> notify the new assignee (and auto-follow them).
    def assigned(todo, actor:)
      assignee = todo.assignee
      return if assignee.nil? || assignee == actor

      todo.follow!(assignee)
      Notification.deliver(
        dedup_key: "assigned:#{todo.id}:#{assignee.id}:#{todo.updated_at.to_i}",
        household: todo.household, user: assignee, actor: actor, notifiable: todo,
        kind:  "assigned",
        title: I18n.t("notification.assigned.title"),
        body:  I18n.t("notification.assigned.body", title: todo.title),
        url:   "/todos/#{todo.id}"
      )
    end

    # A meaningful todo change (e.g. status) -> notify followers except the actor.
    def todo_changed(todo, actor:, summary:)
      notify_followers(
        todo, actor: actor, kind: "todo_changed", notifiable: todo,
        dedup: "todo_changed:#{todo.id}:#{todo.updated_at.to_i}",
        title: I18n.t("notification.todo_changed.title"), body: summary
      )
    end

    # New comment -> notify followers except the commenter.
    def commented(comment, actor:)
      todo = comment.todo
      notify_followers(
        todo, actor: actor, kind: "comment_added", notifiable: comment,
        dedup: "comment_added:#{comment.id}",
        title: I18n.t("notification.comment_added.title"),
        body:  I18n.t("notification.comment_added.body", title: todo.title)
      )
    end

    private

    def notify_followers(todo, actor:, kind:, notifiable:, dedup:, title:, body:)
      todo.followers.where.not(id: actor&.id).find_each do |user|
        Notification.deliver(
          dedup_key: "#{dedup}:#{user.id}",
          household: todo.household, user: user, actor: actor, notifiable: notifiable,
          kind: kind, title: title, body: body, url: "/todos/#{todo.id}"
        )
      end
    end
  end
end
