# CalDAV Two-Way Calendar Sync — Engineering Spec & Delivery Plan

> Status: Approved spec (integrated from a six-role debate-and-refine pass).
> Owner: Delivery Lead. Target: Pantria (Rails 8 / Ruby 3.3.6, MySQL 8.4, Hotwire, Solid Queue).
> Scope: Provider-agnostic CalDAV (app-password) two-way sync. Google-via-OAuth is a later pluggable adapter.

This document is the authoritative spec. Where the team held conflicting red lines, the Delivery Lead's resolution and justification are stated inline under **Decision**.

---

## 1. Summary and Goals

### 1.1 The thinnest genuinely-two-way slice (MVP)

A single household connects **one** CalDAV calendar (URL + username + app-password) and gets **genuinely bidirectional** sync for **single (non-recurring) timed and all-day events**, including deletes:

- Create/edit in Pantria → appears in the external calendar within seconds (immediate push).
- Create/edit on a phone/other device → appears in Pantria within ~5 minutes (recurring poll).
- Delete on either side → removed on the other.
- Same event edited on both sides between polls → **deterministic remote-wins**, the dropped local edit is surfaced via the notification bell (never silently lost).

**Acceptance:** Connect iCloud / Nextcloud / Fastmail. Create "Zahnarzt 14:00" in Pantria → visible in Apple Calendar in seconds. Edit its time on the phone → reflected in Pantria within ~5 min. Delete it on either side → gone on the other. An all-day event for a `Europe/Berlin` household never slides to the previous day.

### 1.2 Explicit non-goals (MVP)

| Non-goal | Why deferred | When |
|---|---|---|
| **RRULE / recurring authoring & two-way** | Re-serializing an RRULE we don't fully model corrupts a series (EXDATE, RECURRENCE-ID, infinite expansion). Pulled recurring events are stored **read-only**. | P2 (read-only render) → P3 (two-way) |
| **sync-token (RFC 6578) as the pull engine** | A poll-cost optimization invisible at 5-min single-household cadence; shipping it primary risks silent total-sync-failure on servers that don't advertise `sync-collection`. | P2 |
| **VTIMEZONE authoring** | Pantria stores UTC and has no floating-time concept; we push timed events as UTC `Z`-form, sidestepping the biggest iCalendar footgun. | Not planned |
| **Field-level / disjoint-field merge** | Requires storing the full prior remote ICS per event (a schema cost the normalized-column model can't back). Degenerates to whole-body remote-wins anyway. | Only if `last_remote_ical` column is later added |
| **Google Calendar (OAuth)** | Needs OAuth2, not app-passwords. The engine is built provider-pluggable so it slots in later untouched. | P3+ |
| **Multiple calendars per instance** | Single-household ⇒ one connection, one collection. | Later |
| **VTODO (task list) sync** | Out of scope; re-enabling later requires re-auditing the comment↔event↔todo loop across the sync boundary. | Later |

### 1.3 Plainly-stated caveats

- **Near-live, not live.** CalDAV has no universal push. **Local→remote is immediate; remote→local is "within a few minutes" (5-min poll).** The UI must never say "live" or "instant." The load-bearing trust signal is the `last_synced_at` relative timestamp ("vor 3 Min.").
- **Provider-agnostic, Google later.** MVP ships the CalDAV app-password path (Apple iCloud, Nextcloud, Fastmail, Radicale, mailbox.org, Yahoo). The settings screen states Google support is coming.
- **Read-only pull is an internal build-order milestone only.** It is never shipped to end users as a labeled feature or a silent half-direction. The first user-facing release is genuinely two-way.

---

## 2. CalDAV Protocol Design

All XML is hand-built with heredocs and parsed with `Nokogiri::XML`, **registering `D:` / `C:` / `CS:` namespace prefixes explicitly** (default-namespace xpath is the classic CalDAV footgun).

### 2.1 Discovery (one-time, settings-screen only — never on the hot path)

Discovery is a settings-screen operation, not part of sync. Run on **"Test & discover"**:

1. `PROPFIND Depth:0` on the user-supplied URL for `{DAV:}current-user-principal`.
2. `PROPFIND Depth:0` on the principal for `{urn:ietf:params:xml:ns:caldav}calendar-home-set`.
3. `PROPFIND Depth:1` on the home-set; filter children whose `resourcetype` includes `{caldav}calendar` and whose `supported-calendar-component-set` advertises `VEVENT`. Read `displayname`, `{CS}getctag`, and `supported-report-set` (to detect `{DAV:}sync-collection`).

**Short-circuit:** if the pasted URL itself `PROPFIND`s as a calendar collection (iCloud principal URLs are non-obvious), skip the chain. Persist the chosen collection's **absolute href** plus `supports_sync_collection` so the pull strategy is chosen **once**, not sniffed every poll.

> **Decision — the client MUST NOT copy `Bring::Client.http_request` verbatim.** Verified: `Bring::Client` uses a hardcoded `BASE_URL`, a single-shot `Net::HTTP.new`, **zero redirect/Location handling**, and a `req_class` case with only GET/POST/PUT. iCloud discovery 301-redirects from the apex / `.well-known/caldav` to `caldav.icloud.com`, and SabreDAV/iCloud emit principal/home-set redirects. A verbatim copy returns a 301 body, Nokogiri parses empty, and discovery silently returns **zero calendars against a valid account**. The CalDAV client therefore adds:
> - Custom `Net::HTTPRequest` subclasses for `PROPFIND` and `REPORT` (assert `Depth` header + body are set, or `Depth:1` silently returns only the collection, not its children).
> - Capped redirect-following (~5 hops) that **re-issues the same verb + body + `Depth`**, carrying `Authorization` **only to the same host**.
> - `.well-known/caldav` bootstrap for bare-host URLs.
>
> An **iCloud discovery fixture is a hard definition-of-done gate** on the discovery PR.

### 2.2 Sync strategy — CTag + per-href ETag diff (MVP baseline); sync-token deferred (P2)

> **Decision — CTag+ETag diff is the MVP pull engine; sync-token is a P2 optimization.** This inverts the original Architect/Dev "sync-token primary" position. Rationale (PO/QA red line, Architect & Dev conceded): CTag+ETag is the **universal floor** every WebDAV calendar server supports — no token-reset failure class. Making sync-token primary risks a "connected" badge over **stale data** on Radicale builds / iCloud token resets that don't advertise or honor `sync-collection` — the worst silent failure for a HARD two-way requirement.

**Pull (MVP):**
1. `PROPFIND Depth:0` `{CS}getctag` on the collection. If the CTag is unchanged since `last_ctag`, **stop** (one cheap request).
2. If changed: `PROPFIND Depth:1` `{DAV:}getetag` on all hrefs. Diff against the stored `remote_href → etag` map to compute `created / updated / deleted`.
3. `calendar-multiget` REPORT to fetch `calendar-data` for **only** the changed hrefs (paginated in batches, e.g. 50 hrefs/REPORT, for large calendars).

**Pull (P2, sync-token):** `{DAV:}sync-collection` REPORT with the stored `sync_token`; server returns per-href responses with new ETags and `404` for deleted hrefs, plus a fresh token. On `invalid-sync-token` (HTTP 409 + `DAV:valid-sync-token`, or some servers 400/410), **clear the token and fall through to a full CTag-style re-sync**.

> Both strategies (and any future provider) converge on **one internal `Changeset` struct** — `{ created:, updated:, deleted: }` of normalized event payloads — so reconciliation is **strategy-agnostic and idempotent** (keyed on `ical_uid`, never on diff position).

### 2.3 Local → remote: PUT / DELETE with ETag preconditions

- **Create:** `PUT` the VEVENT with `If-None-Match: *`. A 412 here means the resource already exists remotely (we pulled it concurrently) → switch to the update path.
- **Update:** `PUT` with `If-Match: <stored etag>`. 200 → store the new ETag. **412 → conflict path (§5.3).**
- **Delete:** `DELETE` with `If-Match: <stored etag>`. 404 → already gone, treat as idempotent success. 412 → remote changed; re-pull, do not delete, surface a notice.

> **Decision — server-assigned href is the source of truth, never a client-guessed path.** Many servers (notably iCloud) assign their own `.ics` href and key uniqueness on **href, not iCalendar UID**. We **mint** the `ical_uid` (`SecureRandom.uuid + "@pantria"`) as the stable **application-layer** identity, but recovery after a died-mid-create retry keys on UID via a `calendar-query` REPORT (or the next pull, which carries the UID), **then** PUTs `If-Match` against the discovered href. This prevents duplicate-on-retry. (Verified concern; proven by a double-perform test.)

### 2.4 Request/response shapes (high level)

| Operation | Verb | Key headers | Body | Success |
|---|---|---|---|---|
| Principal discovery | `PROPFIND` | `Depth: 0` | `<propfind><prop><current-user-principal/></prop></propfind>` | 207 multistatus |
| List collections | `PROPFIND` | `Depth: 1` | `displayname`, `resourcetype`, `getctag`, `supported-report-set`, `supported-calendar-component-set` | 207 |
| CTag poll | `PROPFIND` | `Depth: 0` | `<prop><getctag/></prop>` | 207 |
| ETag diff | `PROPFIND` | `Depth: 1` | `<prop><getetag/></prop>` | 207 |
| Fetch bodies | `REPORT` | `Depth: 1` | `calendar-multiget` w/ hrefs + `calendar-data` | 207 |
| Create | `PUT` | `If-None-Match: *`, `Content-Type: text/calendar` | VEVENT | 201 + ETag |
| Update | `PUT` | `If-Match: <etag>` | VEVENT | 200/204 + ETag |
| Delete | `DELETE` | `If-Match: <etag>` | — | 200/204 |

---

## 3. Library Decision

> **Decision (unanimous): hand-roll `Net::HTTP` + `Nokogiri` for WebDAV; add ONLY the maintained `icalendar` gem for VEVENT; wrap it in our own `Caldav::VeventCodec`. Reject all Ruby caldav gems.**

**Why hand-roll WebDAV.** It is ~6 request shapes (`PROPFIND`, `REPORT` ×2, `PUT`, `DELETE`, `GET`). Every other Pantria outbound integration is hand-rolled `Net::HTTP` (`app/services/bring`, `kaufda`, `chefkoch`). The Ruby caldav/agcaldav gems are thin, years-stale, CI-hostile (no fixtures, surprising network behavior), and would invert house style — a supply-chain / bus-factor risk for self-hosters. They save nothing on the layer where the hard parts live (server quirks, redirects). `Bring::Client#log_failure` already redacts `Bearer|JWT|Basic` headers via `/\A(Bearer|JWT|Basic) (.+)/i`, so the CalDAV `Authorization: Basic` app-password is scrubbed in logs for free.

**Why add `icalendar` (the one gem that earns its keep).** iCalendar is genuinely hard by hand: 75-octet line folding, escaping (`,` `;` newlines), `DATE` vs `DATE-TIME`, `DTSTAMP`/`UID`/`SEQUENCE` semantics, `TZID`. Parsing untrusted server output by regex is a footgun. Pure-Ruby, maintained, no native extension.

> **Wrap it in `Caldav::VeventCodec`** so (a) we control the all-day/UTC encoding decisions deterministically, (b) a gem upgrade can't silently change our wire format without a red test, and (c) we **never re-serialize an RRULE we received** (recurring masters are stored raw). Pin the gem version.

### 3.1 iCalendar scope

| iCalendar feature | MVP | Notes |
|---|---|---|
| `SUMMARY`, `DTSTART`, `DTEND`, `UID`, `SEQUENCE`, `DTSTAMP`, `LAST-MODIFIED` | **In** | `SEQUENCE` bumped on every local edit so servers/clients treat our PUT as newer. |
| Timed events | **In (UTC `Z`)** | We store UTC and have no floating-time concept ⇒ emit `DTSTART:…Z`; no VTIMEZONE authoring. On parse, resolve incoming `TZID`/`VTIMEZONE` → UTC. |
| All-day (`VALUE=DATE`) | **In** | `DTEND;VALUE=DATE` is **exclusive** (`day+1`). See §4.3 for the storage invariant. |
| `RRULE` / `EXDATE` / `RECURRENCE-ID` | **Out (read-only)** | Store master raw; render read-only; **never re-PUT**. |
| `VALARM`, `ATTENDEE`, `ORGANIZER` | **Out** | Not modeled. |
| VTIMEZONE authoring | **Out** | Sidestepped by UTC `Z`-form push. |

---

## 4. Data Model

### 4.1 `CalendarConnection` (new table, single row per household, admin-only)

Mirrors `BringConnection` + CalDAV anchors. Credentials encrypted day one.

```rb
# calendar_connections
household_id            :bigint  not null
server_url             :string
username               :string
encrypts :app_password           # AR encryption — see §4.4
principal_url          :string
calendar_home_url      :string
calendar_href          :string   # the chosen collection (absolute)
calendar_display_name  :string
last_ctag              :string
sync_token             :text      # null in MVP; populated when P2 sync-token lands
supports_sync_collection :boolean default: false  # detected at discovery
status                 :integer   # enum: disconnected | connected | error | auth_error
last_error_code        :integer   # enum: auth | unreachable | not_caldav | conflict | token_reset | partial | rate_limited | unknown
last_error             :text      # sanitized free-text (secondary detail only)
last_synced_at         :datetime
```

> **Decision — add `last_error_code` enum alongside sanitized free-text (UI red line, conceded by all).** Rendering `@connection.last_error` verbatim (as the Bring screen does) means raw HTTP/XML in the UI — a **credential-leak vector** (Basic auth base64s the app-password into headers/exceptions) and fragile view string-matching that breaks de/en parity. The badge/`.flash` render an **i18n'd category** off `last_error_code`; free-text is optional detail **only after sanitization at the persistence boundary**.

### 4.2 `CalendarEvent` sync anchors (added columns)

```rb
ical_uid               :string    # MINTED on local create: SecureRandom.uuid + "@pantria"; stable cross-system key
etag                   :string    # last-seen remote ETag (opaque version token); null until first push
remote_href            :string    # server-assigned href; SOURCE OF TRUTH, never client-guessed
calendar_connection_id :bigint    # nullable: pre-sync local events stay null until first push
deleted_at             :datetime  # tombstone for two-way deletes
sync_origin            :integer   # enum: local | remote — backfill existing rows to 'local'
```

> **Decision — `sync_origin` is a SEPARATE orthogonal column. Do NOT extend `SOURCES` with `"caldav"`.** Verified: `SOURCES = %w[manual comment_extraction todo]` and `task_like?` hard-gates on `source == "manual"`. The two axes are genuinely independent:
> - **`source`** = *semantic provenance* (why the event exists) — drives the keyword loop.
> - **`sync_origin`** = *origin of the last write* (local vs remote) — drives the echo guard.
>
> Overloading `source` with `"caldav"` would make a `comment_extraction` event that also syncs **unrepresentable**, and would freeze a real remote meeting out of the event→todo path. Remote events get `sync_origin = remote`; `source` stays semantic.

### 4.3 All-day storage invariant (a migration-PR decision, not an edge case)

> **Decision — store all-day `starts_at` as the household-tz-midnight-of-the-DATE converted to UTC, round-tripped ONLY through `Household.current.timezone`, never naive `.utc`; `DTEND;VALUE=DATE` is exclusive (`day+1`).**

Verified: `calendar_events` has `starts_at`/`ends_at` as plain UTC `datetime` and an `all_day` boolean — **no date column**. Forcing a floating DATE through a UTC datetime is the exact mechanism that slides all-day events by a day for a `Europe/Berlin` household (Berlin midnight is 22:00/23:00 UTC).

> **Decision — every pull/push reconciliation block MUST wrap work in `Time.use_zone(household.timezone)`.** Verified: `HouseholdTimeZone` is a request-cycle `around_action` (`Time.use_zone`) that does **not** apply inside Solid Queue jobs — the poll/push run with the worker-default zone (likely UTC). Without the wrap, the all-day mapping computes against the wrong zone and **ships a silent day-shift while controller-spec tests pass**. The all-day round-trip test **must run through the job path**.

### 4.4 How remote events coexist with provenance + the keyword loop

> **Decision (RED LINE) — `task_like?` must gate on `source == "manual"` AND `sync_origin == "local"`.** Verified: `task_like?` currently returns `false unless source == "manual"`. If we stamped remote events `source = "manual"` (to make them todo-eligible), **every** pulled remote event containing `kaufen`/`anrufen`/`besorgen` becomes task-like — pulling a real calendar would spawn a **wall of unsolicited todo suggestions on first sync**, the exact keyword-loop multiplication the brief warns against.

```rb
def task_like?
  return false unless source == "manual"
  return false unless sync_origin == "local"   # NEW gate
  # ...existing keyword logic
end
```

Remote-origin events are first-class on the grid but **not auto-todo-eligible**. "Turn a real meeting into a todo" becomes an explicit later opt-in, never an automatic per-poll suggestion. The comment→event→todo loop stays intact: a pulled event is not a comment (so comment-extraction can't fire), and a Todo's `due_on` projection is read-only (never a `CalendarEvent` row, never PUT).

### 4.5 `Notification` plumbing

Verified: `Notification::KINDS = %w[assigned todo_changed comment_added]` (validated whitelist) and `dedup_key` is `presence + uniqueness` (globally unique); `self.deliver` does `find_by(dedup_key:)` on collision (creates nothing).

> **Decision — add `calendar_sync_conflict` (and `calendar_event_removed`) to `KINDS`, and use a VERSION-SCOPED `dedup_key`.** A naive `"calendar_conflict_#{event_id}"` fires **exactly once for all time** — the 2nd/3rd real conflict is silently swallowed, defeating "never surprised by a silent change." Use `"calendar_sync_conflict:#{event_id}:#{remote_etag}"` so each distinct resolution rings the bell once. Spec: a second conflict on the same event produces a second notification.

---

## 5. Two-Way Sync Algorithm

### 5.1 Pull cycle (remote → local), per poll

```
within Time.use_zone(household.timezone):
  CalendarEvent.without_caldav_sync do          # thread-local echo guard
    changeset = provider.fetch_changes(connection)   # CTag+ETag diff → Changeset
    ActiveRecord::Base.transaction do
      changeset.created/updated.each do |remote|
        evt = upsert_by(ical_uid:, calendar_connection_id:)   # idempotent
        if normalized_equal?(evt, remote)        # byte-equal after normalization
          next                                   # NO-OP: do not flip sync_origin, do not notify
        end
        apply(remote) ; evt.sync_origin = :remote
      end
      changeset.deleted.each { |href| tombstone_if_explicitly_deleted(href) }  # §5.4
      connection.update!(last_ctag:, last_synced_at: Time.current)  # advance ONLY after full apply
    end
  end
```

- **Advance `last_ctag`/`sync_token` only after the whole changeset commits** in one transaction. A mid-apply crash re-fetches from the old anchor next poll — idempotent because reconciliation upserts by `ical_uid`.

### 5.2 Push cycle (local → remote), immediate

```
after_create_commit / after_update_commit / after_destroy_commit:
  return if caldav_sync_skipped?                 # without_caldav_sync guard
  return unless household.caldav_connected?
  SyncCalendarEventToCaldavJob.perform_later(event_id, action:)
```

- For **destroy**, capture `ical_uid` / `remote_href` / `etag` in `before_destroy` and pass them **by value** to the job (mirrors `remember_for_bring`) so a destroyed row still DELETEs remotely.
- Job: `retry_on Caldav::Error` (3×, `polynomially_longer`); `discard_on Caldav::AuthError, ActiveRecord::RecordNotFound`.

### 5.3 Conflict resolution

> **Decision — ETag optimistic concurrency (`If-Match` → 412 → re-pull, WHOLE-EVENT remote-wins). The minimal 412 handler ships in the SAME PR as the first PUT. Reject wall-clock last-write-wins. Field-merge is dropped entirely.**

- **Reject wall-clock LWW.** Clock skew between a self-hosted box and iCloud makes "which clock" unanswerable; `DTSTAMP` is client-controlled. Non-deterministic, data-destroying, unauditable.
- **Remote-wins is the deterministic tiebreak.** The external calendar is the shared/authoritative surface (phone notifications, other family devices); Pantria is the ERP overlay.
- **The 412 handler is NOT deferrable.** The moment you `PUT` with `If-Match`, a same-event-both-sides edit **WILL** 412. An unhandled 412 storms `retry_on` against a stale `If-Match` and lands the connection in error; a bare `PUT` without `If-Match` blind-overwrites remote (lost-update). **There is no safe two-way-write state that excludes the 412 branch.**

On 412:
1. Re-`GET` the href, parse the remote VEVENT.
2. Apply **whole-event remote-wins**, store the new etag via `update_columns` (no callback re-fire).
3. Fire **one** notification whenever a local value was **dropped**.

> Field-aware disjoint merge is **dropped even from P2** (Dev's verified catch): detecting which fields the *remote* changed needs the pre-edit remote ICS to diff against, which we don't store (only normalized columns) — so "merge" degenerates to whole-body remote-wins anyway. If ever wanted, it requires a `last_remote_ical` column as its own prerequisite PR.

**User-visible behavior.** Non-blocking, never a modal. Routed through the existing `Notification` bell (`after_create_commit :broadcast_bell`, solid_cable). Copy aligns with remote-wins semantics — **never** "most recent change" (we keep the calendar's version regardless of wall-clock recency; "newer" would be a lie the first time a user's newer local edit is dropped):

> **EN:** "This event was also changed in your connected calendar; we kept the calendar's version."
> **DE:** "Dieser Termin wurde auch in deinem verbundenen Kalender geändert; wir haben die Version aus dem Kalender übernommen."

### 5.4 Echo / loop prevention + idempotency

> **Decision — correctness rests on (a) the `without_caldav_sync` thread-local guard for same-process, and (b) idempotent UID-keyed upsert with normalized-content no-op. ETag-fingerprinting is NOT a correctness mechanism.**

- **(a) Thread-local guard.** Clone `GroceryItem.without_bring_sync` verbatim as `CalendarEvent.without_caldav_sync` (sets `Thread.current[:pantria_skip_caldav_sync]`). Correct because Solid Queue workers are threaded. All pull-time writes run inside it, so applying a remote change never enqueues a local→remote PUT.
- **(b) Durable cross-poll guard.** Upsert keyed on `(ical_uid, calendar_connection_id)`. A pulled body **byte-equal after normalization** (DTSTART/DTEND/SUMMARY/SEQUENCE) to the local row is a **no-op** — it does **not** flip `sync_origin` or fire a notice. Store the post-PUT etag via `update_columns` so it never re-enqueues.
- **Why not ETag-fingerprint:** verified that some servers (SabreDAV/iCloud) re-serialize VEVENTs server-side or don't return the new ETag on `PUT`, so "our write coming back" arrives with a **different** etag — defeating the fingerprint and **falsely** flipping `sync_origin` to `remote` + firing a spurious conflict. ETag is used **only** as the `If-Match` concurrency token.

**Idempotency** is proven by **double-perform**: create job ×2 → exactly one VEVENT per UID; poll ×2 unchanged CTag → zero writes; DELETE re-run on a 404'd href → success.

### 5.5 Delete safety (highest-severity data-loss guard)

> **Decision (RED LINE) — a local event is deleted ONLY on an explicit per-href `404` or a genuine, verified-COMPLETE listing absence. NEVER inferred from a partial/paged/5xx multistatus.**

A truncated REPORT returning 3 of 10 hrefs, reconciled naively against the local set, would delete 7 real events on both sides **and** fire 7 false "event removed" notifications that train users to ignore the bell. A partial/5xx REPORT produces **zero deletions and zero deletion-notifications**, sets `last_error_code = partial`, and is safe to re-run. The remote-deletion notification fires **only** on the explicit-deletion signal. Tombstone (`deleted_at`) makes two-way deletes auditable; a nightly job hard-deletes old tombstones.

---

## 6. Live-Like Cadence

> **Decision — immediate `after_commit` push + a 5-minute recurring poll, exposed as a single config constant. Honest near-live framing; never "live"/"instant."**

Verified `config/recurring.yml`: `bring_pull_all` **and** `poll_inbound_receipts` are **both `every 5 minutes`**. The Architect's 2-minute proposal was withdrawn — 2 min is 2.5× the REPORT traffic against rate-limiting iCloud/Fastmail for latency no household perceives, and the CTag-fallback path is **not** a single cheap REPORT (a CTag change triggers a full `Depth:1 PROPFIND` of all hrefs). 2 min remains a data-driven P2 tweak, not an MVP commitment.

```yaml
# config/recurring.yml
caldav_poll:
  class: CalendarPollJob          # single-household: a plain job, no *AllJob fan-out needed
  schedule: every 5 minutes
  queue: default
  description: "Poll the connected CalDAV calendar and reconcile."
```

- **Push:** immediate via `after_*_commit` job; no-ops without a connection (like `enqueue_bring_create`).
- **Manual "Sync now":** button on the settings screen enqueues the same poll for the impatient.
- **Honest copy:** "Changes you make sync right away; changes from your other devices appear within a few minutes."

---

## 7. Phased Delivery Plan

Each phase is an independently CI-green PR against recorded fixtures (no live server). Read-only pull (PR3) is an **internal build-order milestone** — not marketed to users as "sync"; if exposed for dogfooding it carries an explicit "sending changes not yet enabled" state.

| PR | Scope | Owner roles | Complexity | Exit criteria |
|---|---|---|---|---|
| **PR1 — Foundations** | Migrations (`calendar_connections` + sync anchor columns + `sync_origin` backfill); `CalendarConnection` model w/ `encrypts :app_password`; `last_error_code`/`status` enums; **net-new i18n de/en key-parity spec**; ciphertext≠plaintext spec; Pundit `CalendarConnectionPolicy` (admin-only); settings-screen skeleton (save only, no sync). | Dev, QA, Security | S–M | Migrations reversible; encryption spec green; parity spec green and gating; admin-only enforced. |
| **PR2 — Discovery + connect UI** | `Caldav::Client` (redirect-following, `.well-known` bootstrap, PROPFIND/REPORT subclasses, redaction); `Caldav::Discovery`; two-step "Test & discover → pick collection"; status panel; `last_error_code` mapping. **Metadata only — no event sync.** | Dev, UX, UI, QA | L | Discovery parses Nextcloud + Radicale + **iCloud** fixtures (iCloud fixture is a DoD gate); errors render i18n'd categories, never raw XML. |
| **PR3 — Pull (read half, internal)** | CTag+ETag diff pull → `Changeset` → upsert (`sync_origin = remote`); `Caldav::VeventCodec`; `without_caldav_sync` guard; **`Time.use_zone(household.timezone)` job wrap**; `CalendarPollJob` @ 5 min. | Dev, QA | M–L | All-day round-trip via the **job path** (Berlin no day-slide, exclusive DTEND); unchanged-CTag re-poll → zero writes; no-op normalization verified. |
| **PR4 — Push + minimal 412 (FIRST two-way)** | `PUT`/`DELETE` `If-Match`/`If-None-Match`; `after_commit` push job; mint `ical_uid`; UID-keyed idempotent create-recovery; **minimal 412 remote-wins handler + notification**; tombstone two-way delete. | Dev, QA, UX | M–L | Both-sides edit → 412 → remote wins → exactly one notice → no re-push echo → no retry storm; double-perform → one VEVENT per UID; **delete only on explicit 404 / complete-listing absence** (truncated-multistatus test green). |
| **PR5 — Hardening + parity sweep** | Failure taxonomy (auth/5xx/partial/token-reset); `Notification` KINDs + version-scoped `dedup_key`; recurring events rendered **visibly non-editable** (read-only view/disabled form); de/en sweep; mobile/a11y pass. | Dev, QA, UX, UI | M | Partial sync → zero deletes/zero false notices; recurring synced event cannot be edited in the flat form; full de/en parity. |
| **P2 — Optimizations** | sync-token (detect-and-prefer; CTag+ETag kept as permanent fallback, token-reset → full-resync tested); richer conflict/status UX (sync history, [View history], header sync badge memoized via solid_cable). | Architect, Dev, QA | L | sync-token path + token-reset resync tested; CTag fallback still green. |
| **P3+ — Recurring two-way & Google** | RRULE two-way (RECURRENCE-ID overrides, byte-stable round-trip gate); `GoogleOauthProvider` slotted into the existing port (consent/refresh) implementing the same four methods so reconciliation is untouched. | Architect, Dev, QA, UX | XL | Round-trip byte-stability per RRULE shape; Google adapter passes the same Changeset contract tests. |

**Provider-pluggable port (built in MVP, cheap):** a duck-typed `CalendarProvider` responds to `discover_calendars`, `fetch_changes(connection) → Changeset`, `push_event(event) → {href, etag}`, `delete_event(href, etag)`. Reconciliation talks **only** to the port and the normalized `Changeset` — CalDAV-isms (hrefs, ctags) never leak past the provider; `etag` is an opaque version token. So conflict/echo/tombstone logic is written **once** and `GoogleOauthProvider` changes nothing in reconciliation.

---

## 8. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Delete-vs-absent data loss** (partial/paged/5xx multistatus → mass false deletes) | **Critical** | Delete only on explicit `404` / verified-complete absence. Partial → zero deletes, zero notices, `last_error=partial`, safe re-run. Failing-first truncated-multistatus test before two-way delete ships. |
| **Protocol variance across servers** (iCloud well-known redirect, non-obvious principal URLs, href escaping, ETag quoting, sync-token support) | High | Hand-rolled client with redirect-following + `.well-known` bootstrap. CTag+ETag universal baseline. Multi-provider scrubbed fixture corpus = the test oracle; **acceptance provider list == fixture provider list**. |
| **All-day / DST day-shift** (no date column; jobs run outside `HouseholdTimeZone`) | High | Strict UTC-midnight-of-DATE invariant; **wrap all sync jobs in `Time.use_zone(household.timezone)`**; exclusive DTEND; Berlin round-trip test via the job path. |
| **Echo loops** (push re-applied on next poll; comment→event→todo multiplying) | High | Thread-local guard + UID-keyed normalized no-op upsert; `task_like?` gates on `source == "manual"` AND `sync_origin == "local"`; no-multiply regression tests. |
| **Conflicts** (same-event both sides) | Medium | ETag `If-Match` → 412 → re-pull whole-event remote-wins + one notice. Ships **with** the first PUT. Reject wall-clock LWW. |
| **Duplicate-on-retry** (job dies after server create, before storing href) | Medium | Recovery keys on iCalendar UID (`calendar-query` REPORT / next pull), server-assigned href is truth. Double-perform test → one VEVENT per UID. |
| **Token reset** (server invalidates sync-token) | Medium (P2) | On `invalid-sync-token` → clear token → full CTag re-sync (idempotent on UID). CTag+ETag stays permanent fallback. |
| **Recurring (RRULE) corruption** | High | Read-only in MVP; store master raw, never re-serialize/re-PUT; UI renders recurring synced events non-editable (engine guard alone is insufficient). |
| **Security / credential leakage** | High | `encrypts :app_password` (AR encryption is **live**, derived from `SECRET_KEY_BASE`); redact `Authorization` in logs (Bring pattern) **and** sanitize `last_error` at the persistence boundary (it renders in admin UI); admin-only Pundit; redact telemetry span attributes. Tests assert ciphertext≠plaintext and absence of the app-password substring in logs/`last_error`. **Caveat:** rotating `SECRET_KEY_BASE` makes stored passwords unreadable — document "reconnect after rotation." |
| **Notification spam / silent swallow** | Medium | Version/etag-scoped `dedup_key`; `KINDS` whitelist change in same PR; spec proves a second conflict → a second notice. |

---

## 9. Test Strategy (CI without a live server)

**Transport seam.** `Caldav::Client` (Net::HTTP + Nokogiri) returns parsed structs; all diff/reconcile/conflict logic lives in **pure services** fed parsed inputs (mirrors `spec/services/bring/{client_spec,pull_spec}.rb`). `WebMock.disable_net_connect!` is already on — any accidental live call **fails** the suite. **No VCR** — house style is checked-in XML fixtures stubbed via `stub_request`.

**Fixture corpus IS the oracle** — `spec/fixtures/caldav/`, scrubbed real captures per quirk: discovery (principal/home-set/list), CTag/ETag diff, multiget bodies, `PUT 201+ETag`, `PUT 412`, invalid-sync-token; all-day `VALUE=DATE` (exclusive DTEND) vs timed `TZID`/`VTIMEZONE` vs UTC-Z; ETag with/without quotes and `W/` weak prefix; href absolute/relative/percent-encoded; a 207 where one href is 404/500 inside an otherwise-200 multistatus. **The acceptance provider list must equal the fixture provider list** (if iCloud is in acceptance, an iCloud fixture is a DoD gate).

**Per-phase named tests:**

- **PR1:** ciphertext≠plaintext at the DB column; **de/en key-parity spec** (flatten both YAMLs, assert symmetric key sets); Pundit denies non-admin.
- **PR2:** discovery parses Nextcloud/Radicale/**iCloud** fixtures (incl. redirect + non-obvious principal); 401 → actionable app-password copy, never raw XML.
- **PR3:** all-day round-trip **through the job path** (Berlin no day-slide, exclusive DTEND); DST spring-gap/fall-back don't crash; unchanged-CTag re-poll → zero writes; remote body normalized-equal → no-op (no `sync_origin` flip, no notice); pull remote `"kaufen"` event → **zero Todos, zero push jobs**.
- **PR4:** both-sides edit → 412 → remote wins → exactly one notice → no re-push echo → no retry storm; 412-storm idempotency (two queued pushes, second no-ops); double-perform create → one VEVENT per UID; delete only on explicit 404 / complete absence; **partial/5xx REPORT → zero deletions, zero deletion-notices**.
- **PR5:** auth/5xx/token-reset full-resync; second conflict on same event → second notification; recurring synced event is non-editable in the UI; **de-locale rendering** snapshot (badge wraps label+timestamp `<640px`, never truncates `"Synchronisierung fehlgeschlagen"`).
- **Optional (tagged, not default CI):** integration spec against a disposable Radicale Docker container to check reality before release.

---

## 10. Open Questions for the Product Owner

The Delivery Lead has pre-resolved most open items (see **Decision** blocks). These genuinely need your call:

1. **Which providers to validate first?** Acceptance currently names iCloud / Nextcloud / Fastmail. **The acceptance list must equal the fixture corpus list.** Which CalDAV server(s) does *your* household actually use? If iCloud stays in acceptance, capturing a scrubbed real iCloud discovery+sync fixture is a hard DoD gate for the discovery PR (its well-known redirect + non-obvious principal URLs are the riskiest surface). If not, naming Nextcloud/Radicale/Fastmail as P0 reduces discovery effort.
2. **Conflict-resolution UX.** Confirm **silent remote-wins + one non-blocking bell notification** ("we kept the calendar's version") is acceptable — i.e. a Pantria edit *can* be replaced (the user redoes it), with no merge/keep-both UI in v1. A keep-mine/keep-theirs screen is materially larger and is proposed for P2+.
3. **Is RRULE/recurring in v1?** Recommendation: **no** — pulled recurring events render **read-only** ("edit in your calendar app"); Pantria authors no recurrence in v1. Two-way recurring is P3 (its own DoD gate). Confirm you accept read-only recurring for launch.
4. **App-password onboarding.** Confirm the per-provider help (picker that pre-fills the URL + links to that provider's app-password page) is the v1 onboarding, and that the in-UI copy may state Google support is "coming later." The account-vs-app-password mistake is the #1 first-connect failure — a 401 will render actionable guidance, not a generic error.
5. **Disconnect behavior (locked pending your nod).** Recommendation/lean: **keep synced events as local copies, strip remote anchors, flip `sync_origin = local`**, with confirm copy: *"Disconnect? Your synced events stay in Pantria but will no longer update from your calendar."* Confirm this single outcome (vs. an explicit keep-vs-clear two-option dialog, which is a larger UI cost) so the de/en confirm copy can be finalized in the MVP settings PR.
