# Todos

A shared, collaborative task list for the household. Every member sees the
same todos; anyone can create, edit and move them, and admins can delete.

## States

Each todo has one of three fixed states — `open` → `in_progress` → `done`
(`offen` / `in Arbeit` / `erledigt` in the German UI). The list is grouped by
state, and a one-tap pill advances a todo to its next state:

- The row is replaced **in place** via Turbo Stream — no column jump, no
  viewport reflow.
- Entering `done` stamps `completed_at`; leaving it clears the stamp.
- Illegal jumps and no-op self-transitions (`open → open`) are rejected by the
  model and fire **no** follower notification.

The state set is a validated string constant (`Todo::STATES`), mirroring the
`GroceryItem::STATUSES` precedent — there is no workflow engine or
admin-editable state table. `archived_at` is a separate visibility flag, not a
state.

## Assignment & follow

- **Assign a member.** Pick one household member as the `assignee`. Assigning
  someone other than yourself creates a notification for them and (if they have
  a push subscription) fires one Web Push — see [Notifications &
  push](#notifications-push). Assignment auto-follows the assignee.
- **Follow / unfollow.** Any member can follow a todo to be notified of
  meaningful changes (status, assignee, due date, new comment). You are never
  notified of your own actions, and an assignee who also follows gets a single
  message, not two.

The assignment trigger is deliberately narrow — it fires only when the assignee
actually changed, is non-nil, and is not the person making the change — so a
plain edit or a self-assignment enqueues zero pushes.

## Comments

Members discuss a todo inline. Posting a comment renders it immediately via the
Turbo Frame form response (no Action Cable dependency); other members see it on
their next navigation. Comments are todo-scoped (`TodoComment`), and a comment
author or an admin can delete one.

Comments are also the input for the German date-detection loop: when a comment
mentions a date, Homestead offers to turn it into a calendar entry. See
[Calendar → suggestions from comments](calendar.md#suggestions-from-comments).

## Notifications & push

Every notifiable event (assignment, a followed change, a new comment) writes a
first-class `Notification` row. That ledger is the reliable channel — it powers
the top-nav **bell** with an unread count and deep-links straight to the todo,
and it works on every device regardless of push support. A `dedup_key` unique
index makes delivery idempotent (the same event twice collapses to one row);
reading via the bell **or** via a push marks the same row read.

Web Push is an additional delivery channel layered on top:

- Members opt in with an explicit tap (never a cold permission prompt). The
  `push_subscribe` Stimulus controller registers a `PushSubscription`, deduped
  on `SHA256(endpoint)`.
- `DeliverPushJob` signs the VAPID request and POSTs the payload; a `410`/`404`
  response hard-deletes the dead subscription so the job never retry-storms.
- The service worker's `push` handler shows the notification and
  `notificationclick` focuses an open tab at the deep-link (or opens one).
- Where push is unavailable (iOS without an installed PWA, desktop, denied
  permission) the feature degrades visibly to the bell.

See [PWA & Android](../pwa-android.md) for installation and the VAPID
environment variables.

## Code references

- Models: [`app/models/todo.rb`](https://github.com/SGraef/Homestead/blob/main/app/models/todo.rb),
  [`app/models/notification.rb`](https://github.com/SGraef/Homestead/blob/main/app/models/notification.rb),
  [`app/models/push_subscription.rb`](https://github.com/SGraef/Homestead/blob/main/app/models/push_subscription.rb)
- Controllers: [`app/controllers/todos_controller.rb`](https://github.com/SGraef/Homestead/blob/main/app/controllers/todos_controller.rb),
  [`app/controllers/notifications_controller.rb`](https://github.com/SGraef/Homestead/blob/main/app/controllers/notifications_controller.rb)
- Push delivery: [`app/jobs/deliver_push_job.rb`](https://github.com/SGraef/Homestead/blob/main/app/jobs/deliver_push_job.rb)
- Subscribe controller: [`app/javascript/controllers/push_subscribe_controller.js`](https://github.com/SGraef/Homestead/blob/main/app/javascript/controllers/push_subscribe_controller.js)
