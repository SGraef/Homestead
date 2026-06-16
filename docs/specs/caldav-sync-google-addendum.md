# Google-First Addendum to the Calendar-Sync Spec

The household uses **Google Calendar**, and Google removed CalDAV app-password
access — so the first provider is **Google Calendar API + OAuth**, not CalDAV.
The shared reconciliation engine, data model, conflict policy (remote-wins +
one bell notice), echo guard, and read-only-recurring decision from
`caldav-sync.md` all stand. Only the **provider** and a few anchors change.

## Provider mapping (the pluggable port, Google implementation)

The port stays `discover_calendars`, `fetch_changes(connection) → Changeset`,
`push_event(event) → {remote_id, etag}`, `delete_event(remote_id, etag)`.
`GoogleCalendarProvider` implements them over the Google Calendar API v3 (JSON
REST via Net::HTTP, consistent with the Bring/Marktguru service style):

| Port operation | Google Calendar API |
|---|---|
| discover_calendars | `GET /users/me/calendarList` |
| fetch_changes (incremental) | `GET /calendars/{id}/events?syncToken=…` → items with `status:"cancelled"` are **explicit deletes** (no delete-vs-absent guessing — strictly better than CalDAV); response carries the next `nextSyncToken` |
| fetch_changes (first / `410 Gone` token) | full `events.list` (paged), then store `nextSyncToken` |
| push_event (create) | `POST /calendars/{id}/events` |
| push_event (update, conflict-guarded) | `PUT /calendars/{id}/events/{eventId}` with `If-Match: <etag>` → `412` ⇒ remote-wins |
| delete_event | `DELETE /calendars/{id}/events/{eventId}` with `If-Match` → treat `404/410` as already-gone |

**Why Google is cleaner than CalDAV here:** native incremental **syncToken**
(no CTag/ETag-diff machinery), **explicit cancelled-status deletes** (kills the
critical delete-vs-absent data-loss risk), and optional **`events.watch`
webhooks** for closer-to-live push (deferred; 5-min poll is the baseline).

## OAuth (the cost of Google)

Self-hosted ⇒ the operator supplies the OAuth client. Stored on the single
`CalendarConnection` (admin-only, encrypted):

- `client_id`, `client_secret` (encrypted) — pasted into settings.
- Authorization-code flow: `Connect` → Google consent → `/calendar/google/callback`
  → exchange code → store `access_token` (encrypted), `refresh_token`
  (encrypted), `token_expires_at`. Refresh on expiry (`refresh_token` grant).
- Scope: `https://www.googleapis.com/auth/calendar`.
- Redirect URI must match the instance's stable HTTPS URL (documented gotcha);
  consent screen "In production" so refresh tokens don't expire in 7 days.

## Data-model deltas vs the CalDAV spec

- `CalendarConnection`: `provider` ("google"), `client_id`, `client_secret`(enc),
  `access_token`(enc), `refresh_token`(enc), `token_expires_at`, `calendar_id`,
  `sync_token`, `status`, `last_error_code`, `last_synced_at`. (No CalDAV
  url/username/app_password in the Google row; CalDAV columns added when that
  provider lands.)
- `CalendarEvent` anchors: `remote_id` (Google event id) **replaces**
  `remote_href`; keep `etag`, `calendar_connection_id`, `sync_origin`
  (local|remote, default local), tombstone for two-way delete.
- Keyword-loop red line unchanged: `task_like?` gates on
  `source == "manual"` **and** `sync_origin == "local"`.

## Revised phasing (Google-first)

1. **PR1 — Foundations** (this PR): `calendar_connections` + `CalendarEvent`
   sync-anchor migrations; `CalendarConnection` model with `encrypts`; provider
   port + `CalendarProvider` registry; admin-only Pundit policy; settings-screen
   skeleton (paste client id/secret, shows status — no OAuth yet); i18n parity;
   ciphertext≠plaintext spec.
2. **PR2 — OAuth connect**: authorization-code flow, callback, token storage +
   refresh; calendar picker (`calendarList`); test/connected/error status.
3. **PR3 — Pull (internal)**: `events.list` + syncToken → Changeset → upsert
   (`sync_origin = remote`) with `without_caldav_sync`-style guard; jobs wrapped
   in `Time.use_zone(household.timezone)`; `CalendarPollJob` @ 5 min.
4. **PR4 — Push + 412 (first two-way)**: `after_commit` push; create/update/
   delete; remote-wins 412 handler + one notice; cancelled-status deletes.
5. **PR5 — Hardening**: failure taxonomy, token-refresh edge cases, read-only
   recurring rendering, de/en + a11y sweep.
6. **Later**: `events.watch` webhooks (closer-to-live); CalDAV provider
   (Apple/Nextcloud/Fastmail) on the same port.
