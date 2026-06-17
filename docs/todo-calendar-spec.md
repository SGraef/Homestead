All repo facts verified: `service_worker.js.erb` has only install/activate/fetch (no push/notificationclick), `GroceryItem.without_bring_sync` thread-local guard confirmed at lines 50-59, `STATUSES`/`ROLES` constant pattern confirmed, `households.timezone` defaults `"UTC"`, `token_digest` unique-index precedent confirmed, `meal_plan_path(date:)` nav confirmed, User#name nullable, cable production adapter is `redis` with no `redis`/`solid_cable` gem. Now writing the spec.

# Homestead Feature Spec — Collaborative Todos, PWA Push, Comments & Keyword-Driven Calendar

**Status:** Approved engineering spec & phased delivery plan
**Owner:** Delivery Lead
**Stack:** Rails 8 / Ruby 3.3.6 · MySQL 8.4 · Hotwire (Turbo + Stimulus + Importmap, ERB, no Node build) · Sorcery · Pundit · Solid Queue · RSpec + FactoryBot + Cypress · OpenTelemetry (opt-in) · single-household-per-instance

---

## 1. Summary & Goals

### What we're building
A collaborative **Todo** domain for the single household, with states, member **assignment**, **follows**, and **comments**; a from-scratch **Web Push** notification stack (currently nonexistent); an in-app **Notification** ledger that doubles as the reliable fallback; a server-rendered **Calendar** that displays events and projects todo due-dates; and a **suggest-then-confirm** German keyword/date extraction loop between comments/todos and the calendar.

### Thinnest valuable MVP (Phase 1–4)
A household member can **create → assign → comment on → complete** a todo with three states. Assigning a member fires **one push notification** to the assignee on their installed Android PWA (and degrades visibly everywhere else). Every notification is also a persisted in-app row reachable from a top-nav bell, so the feature delivers value **even if push never works on a given device**. No calendar and no NLP are required to ship this.

### Design decisions locked across all six roles (keystones)
1. **C5/C7 generation is SUGGEST-then-CONFIRM, never silent auto-create**, in every phase. A human click gates every generated event/todo. This single decision simultaneously contains German-parser false positives *and* dissolves loop-prevention into a human gate.
2. **Notification is a first-class persisted row, not fire-and-forget push.** Push is one *delivery channel*; the bell/list, read-state, deep-linking, idempotency, and the iOS/desktop fallback all fall out of one table. This ledger ships **with the first assignment push**, not deferred.
3. **Todo state = a validated string constant** (`STATES = %w[open in_progress done]`), mirroring the confirmed repo precedent `GroceryItem::STATUSES` (`app/models/grocery_item.rb:13`) and `Membership::ROLES` (`app/models/membership.rb:7`). No workflow gem, no admin-editable state table.
4. **Loop-prevention is structural, two-layered**: the confirmed `GroceryItem.without_bring_sync` thread-local guard pattern (`app/models/grocery_item.rb:50-59`) copied as `CalendarEvent.without_extraction` / `Todo.without_extraction` to suppress the after-commit echo *at source before `perform_later`*, **plus** a provenance enum gating scan-eligibility. Never heuristic "did a push fire" logic.
5. **Live broadcast is NOT free infra and is NOT an MVP dependency.** Verified: `config/cable.yml` production uses `adapter: redis`, but **no `redis` and no `solid_cable` gem** is in the Gemfile and there is **zero broadcast usage** in the repo. MVP renders the bell on next navigation. Live push-down is a separate increment that first adds `solid_cable`.
6. **Hand-rolled ERB calendar grid, never FullCalendar.** Homestead dark mode works only by overriding tokens under `:root[data-theme="dark"]`; a vendored lib ships hardcoded colors that won't flip (bright-white in dark mode) plus a 200KB+ bundle that is **not** in `PRECACHE_URLS` (verified `service_worker.js.erb:22` — `cacheFirst` is cache-on-first-use, not precache).
7. **PushSubscription dedup is a unique index on `SHA256(endpoint)`**, never the raw endpoint, mirroring the confirmed `api_tokens.token_digest` / `invitations.token_digest` precedent (`db/schema.rb:50,132`) — a raw long-endpoint unique index fails MySQL 8.4 utf8mb4's 3072-byte prefix limit.

### Non-goals (explicit)
- **No admin-editable / custom todo states.** Fixed three. `archived` is a separate `archived_at` visibility flag (not a lifecycle state); `canceled` is deferred to explicit request.
- **No silent auto-creation** of calendar events or todos from text, ever.
- **No FullCalendar / toast-ui / CDN calendar lib** for month/week/day rendering.
- **No drag-create/resize, no event overlap/collision layout, no week view** in first calendar slice (these are the genuinely expensive parts, not the time-axis).
- **No recurring events (RRULE)** — each event is a single instance.
- **No inline character-offset highlighting** of detected dates (XSS/off-by-one through ERB escaping); suggestions render as a standalone chip.
- **No multi-assignee** — single nullable `assignee_id`.
- **No analytics/opt-out-rate dashboards** — meaningless at 3–5 users; success is concrete observable behavior.
- **No NLP/Chronic dependency** — Chronic is English-only; hand-rolled deterministic German regex/rules.
- **No blocking the Todo MVP on push working on iOS.**

---

## 2. User Stories & Acceptance Criteria

### C1 — Todo list with states

**Story:** As a household member I create todos and move them through `offen → in Arbeit → erledigt`.

- **Given** I am authenticated, **When** I submit a new todo with a title, **Then** it persists `belongs_to :household`, `status: "open"`, `creator_id: current_user.id`, and appears in the list grouped under *Offen*.
- **Given** a todo in `open`, **When** I tap the next-state pill, **Then** the row is replaced in place via Turbo Stream (no column jump, no viewport reflow) and `status` becomes `in_progress`.
- **Given** a todo, **When** it transitions to `done`, **Then** `completed_at` is set.
- **Given** any `(from, to)` transition, **When** it is illegal (e.g. an undefined jump) **or** a no-op self-transition (`open → open`), **Then** the model rejects/ignores it and **no** follower "change" notification is enqueued.
- **Given** a non-admin member, **When** they attempt to destroy a todo, **Then** Pundit denies it (destroy is admin-gated); any member may create/update.

### C2 — Assign a member → push the assignee

**Story:** As a member I assign a todo to someone and they get a push.

- **Given** a todo, **When** I assign member X (`X != me`, X non-nil) via the fixed avatar/toggle row over `Household.current.users`, **Then** a `Notification(kind: "assigned")` row is created for X and a `DeliverPushJob` is enqueued.
- **Given** X has an installed Android PWA with an active subscription, **When** the job runs, **Then** X receives a push within seconds, and `notificationclick` opens the anchored deep-link (`/todos/123`) focusing an existing client if open, else `openWindow`.
- **Given** X has **no** active subscription (iOS-not-installed/desktop/unsupported), **When** assigned, **Then** no push is sent, the in-app bell shows the notification on X's next navigation, and `UserMailer` is the fallback channel.
- **Given** a no-op save or a self-assignment (`X == me`), **When** the todo is saved, **Then** **zero** push jobs are enqueued. *(QA red line: trigger is guarded on `saved_change_to_assignee_id?` + non-nil + non-actor — never a blanket `after_update_commit`.)*

### C3 — Follow a todo → push followers on change *(P2)*

**Story:** As a member I follow a todo and get notified of meaningful changes.

- **Given** I follow a todo (auto on assignment; opt-in on comment), **When** the `status`, `assignee`, `due`, or a **new comment** changes (the curated allowlist), **Then** I get one notification — **unless** I am the actor (self-suppressed).
- **Given** I am both assignee and follower, **When** an event fires, **Then** I receive **one** message, not two (dedup).
- **Given** the same todo is edited 5× within the coalescing window, **Then** I receive **≤1** coalesced delivery per follower.
- **Given** a description typo-fix or no-op save, **Then** **no** follower notification fires.
- **Given** I tap the follow bell in MVP (before C3 push lands), **Then** it drives a real in-app notification row — it is **never** a silent no-op. *(UX red line.)*

### C4 — Comments on todos

**Story:** As a member I comment on a todo.

- **Given** a todo, **When** I post a comment, **Then** `TodoComment(household, todo, user, body)` persists and the thread renders my comment immediately via the Turbo Frame form response (zero Cable dependency).
- **Given** other members have the page open, **Then** they see the new comment live **only after** the `solid_cable` broadcast increment ships (P2); until then it appears on next navigation.

### C5 — Calendar entries from comment text *(P3, suggest-then-confirm)*

**Story:** As a member, when my comment mentions a German date, I'm offered a calendar entry.

- **Given** a comment "Termin am 5. Mai um 14 Uhr", **When** committed, **Then** `ExtractCalendarEventsJob` runs after-commit and surfaces a standalone chip beneath the comment: *"Termin erkannt: 5. Mai 14:00 — In Kalender übernehmen?"*.
- **Given** I click the chip, **Then** a `CalendarEvent(source: "comment_extraction", source_record: comment)` is created in `Household.current.timezone`, stored UTC (14 Uhr Berlin → 13:00 UTC winter / 12:00 UTC summer).
- **Given** a negative phrase ("ich habe 5 Äpfel gekauft", "Seite 14", "5 Minuten") or an ambiguous parse ("14 Uhr" with no day), **Then** **no** chip appears.
- **Given** I dismiss a chip, **Then** it never re-nags (dismissal persisted by `comment_id + span-hash`); editing the comment invalidates dismissal only for changed spans.

### C6 — In-app calendar *(P2 for display + due-projection; P3 for extraction-fed events)*

**Story:** As a member I see events and todo due-dates on a calendar.

- **Given** the calendar, **When** I open it, **Then** I see a server-rendered **month** grid with `data-cal-day="YYYY-MM-DD"` hooks, an **agenda** list, and a simple **day** view, navigated by `?date=` Turbo Frame links copying `meal_plan_path(date: …iso8601)` (`app/views/meal_plans/show.html.erb:6,13`).
- **Given** todos with `due_on`/`due_at`, **Then** they project onto the grid **read-only** with a distinct accent + legend (no NLP, no loop risk).
- **Given** a day with more events than the chip cap, **Then** a "+N weitere" overflow link appears; long German titles ellipsis with full text in `title=` (no horizontal scroll at 360px).

### C7 — Todos from calendar entries *(later, bidirectional loop)*

**Story:** As a member, a calendar entry can suggest a todo.

- **Given** a **manually-created** event whose text matches a trigger, **Then** a "Aufgabe anlegen?" chip is offered; clicking creates `Todo(source: "calendar_extraction", source_calendar_event_id: event.id)`.
- **Given** an event with `source != "manual"` (already generated from a comment), **Then** it is **never** re-scanned and **never** renders a suggestion chip.
- **Given** a comment→event→todo cascade, **Then** it settles in an **asserted exact** job count and row count; re-saving a generated record yields **zero** new extraction enqueues.

---

## 3. Data Model

All tables `belongs_to :household` (reached via `Household.current`), mirroring `stores`/`products`/`offers`. Data is shared across all members; authz is per-household.

### `todos`
| Column | Type | Notes |
|---|---|---|
| `household_id` | FK, indexed | |
| `creator_id` | FK→users, nullable | |
| `assignee_id` | FK→users, nullable | single assignee ("assign someone") |
| `title` | string | |
| `description` | text | |
| `status` | string, default `"open"` | `validates inclusion: { in: STATES }`, `STATES = %w[open in_progress done].freeze` |
| `due_on` | date, nullable | projected onto calendar (C6a) |
| `due_at` | datetime, nullable | UTC |
| `completed_at` | datetime, nullable | set on `→ done` |
| `archived_at` | datetime, nullable | visibility flag, **not** a status |
| `source` | string, default `"manual"` | `%w[manual calendar_extraction]` |
| `source_calendar_event_id` | FK→calendar_events, nullable | provenance for C7 |

`has_many :todo_comments, :todo_follows`. Guarded `transition_to`; transition validation in the model. `Todo.without_extraction` thread-local guard.

### `todo_comments`
| Column | Type | Notes |
|---|---|---|
| `household_id`, `todo_id`, `user_id` | FK | todo-scoped (no polymorphism; YAGNI) |
| `body` | text | C5 extraction input + C3 trigger |

### `todo_follows` (join)
| Column | Type | Notes |
|---|---|---|
| `todo_id`, `user_id` | FK | **unique index** `(todo_id, user_id)` |

Auto-follow on **assignment** (high intent). Follow-on-comment is **opt-in/togglable**, not automatic.

### `push_subscriptions`
| Column | Type | Notes |
|---|---|---|
| `user_id` | FK | per-user-private (data is household-shared, subscriptions are not) |
| `household_id` | FK | consistency |
| `endpoint` | text | the actual push POST target |
| `endpoint_digest` | string | **unique index**, `SHA256(endpoint)` — mirrors `api_tokens.token_digest` |
| `p256dh`, `auth` | string | Web Push keys from `subscription.toJSON().keys` |
| `user_agent` | string | future "manage devices" |
| `last_used_at` | datetime | |

One user → many subscriptions (phone + desktop). 410/404 on delivery → hard-delete the row.

### `notifications` (first-class ledger — ships in MVP)
| Column | Type | Notes |
|---|---|---|
| `user_id` | FK | recipient |
| `notifiable_type`, `notifiable_id` | polymorphic | → Todo / TodoComment |
| `kind` | string | `%w[assigned todo_changed comment_added]` |
| `payload` | json | `{title, body, url, tag}` (≤4KB push limit) |
| `url` | string | anchored deep-link, e.g. `/todos/123#comment-456` |
| `dedup_key` | string | **unique index** — idempotency (same event twice = one row) |
| `read_at` | datetime, nullable | read via push **or** bell marks the same row |

> **Idempotency ≠ coalescing.** The unique index gives idempotency only. Coalescing (5 distinct edits → 1 notification) is a **separate** windowed/debounced mechanism that lands with C3.

### `calendar_events` *(P2 model; P3 extraction)*
| Column | Type | Notes |
|---|---|---|
| `household_id` | FK | |
| `title` | string | |
| `starts_at`, `ends_at` | datetime | **UTC**; iCal-compatible shape for cheap export later |
| `all_day` | boolean | |
| `source` | string, default `"manual"` | `%w[manual comment_extraction todo]` |
| `source_record_type`, `source_record_id` | polymorphic, nullable | provenance → Comment/Todo; **primary dedup key** (one comment → ≤1 event regardless of text edits) |

`CalendarEvent.without_extraction` thread-local guard. Extractor jobs use `find_or_create_by`/`upsert` and `rescue ActiveRecord::RecordNotUnique` so concurrent retries skip cleanly (no 500). **No content-hash unique index** (brittle — one edited word forks a second event).

### `suggestion_dismissals` *(P3)*
| Column | Type | Notes |
|---|---|---|
| `todo_comment_id` | FK | |
| `span_hash` | string | **unique index** `(comment_id, span_hash)` — declined chip never re-nags |

### Keyword / extraction rules (not a table)
`GermanDateExtractor` is a **service object** — a fixed ordered set of anchored regexes over German vocabulary, not a DB-configurable keyword table. Trigger nouns (`Termin`, `Frist`, `Deadline`, `Treffen`) raise confidence / become the title. (Reuses the spirit of the `OfferCategoryKeyword` downcased-substring precedent for trigger words, but the date grammar is code.)

---

## 4. Technical Design

### (a) Web Push stack — from scratch, XL, its own PR stack

- **Gem:** pin the **maintained `web-push`** fork (pure Ruby, no native deps, signs VAPID JWT + encrypts payload) — **not** the unmaintained `webpush`. Confirmed neither is in the Gemfile today.
- **VAPID keypair:** one per deployment in ENV/credentials (`VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT=mailto:`). Public key exposed via a tiny `/push/vapid_public_key` endpoint or meta tag. **Document: rotation invalidates all subscriptions (force re-subscribe-all).**
- **PushSubscription lifecycle:** `pushManager.subscribe({userVisibleOnly: true, applicationServerKey})` → POST JSON to `PushSubscriptions#create` → persist `endpoint`/`endpoint_digest`/`p256dh`/`auth`. On delivery, **410/404 hard-deletes the row** (pruning mandatory in the *first* delivery impl, or the job retry-storms dead endpoints). Rotated endpoints create transient duplicate rows cleaned by the next 410 prune — acceptable.
- **Solid Queue delivery:** `DeliverPushJob(notification_id)` loads the recipient's subscriptions, POSTs each via `web-push`, prunes on 410/404. Mirrors `ProcessReceiptJob` `retry_on`/`discard_on` (incl. `discard_on ActiveRecord::RecordNotFound`). Default queue (`config/queue.yml` `*,!receipts` picks up new queues free).
- **Service-worker handlers** (`app/views/pwa/service_worker.js.erb` — confirmed only `install`/`activate`/`fetch` today): add a `push` listener (`event.waitUntil(self.registration.showNotification(...))` parsing the JSON payload) and a `notificationclick` listener (focus an existing client at `payload.url`, else `clients.openWindow`).
- **Stimulus subscribe + permission UX:** `push_subscribe_controller.js`. **Explicit user-gesture opt-in only** — never an on-load `Notification.requestPermission()` (a denied origin is irreversible). A soft pre-ask sheet (*"Push aktivieren, damit du Zuweisungen sofort siehst" / "Aktivieren" / "Später"*) gates the native prompt, triggered when a member first assigns/follows.
- **Graceful degradation with visible recovery states** (silence after an opt-in tap is a *bug*):
  - denied → *"Benachrichtigungen sind blockiert; du siehst Updates in der App-Glocke"*
  - iOS-not-installed → *"Zum Home-Bildschirm hinzufügen"* hint (web push only works for installed PWAs on iOS 16.4+)
  - unsupported → bell-only banner
  - Fallback channel everywhere: in-app bell + `UserMailer`.

### (b) Notification fan-out — async, deduped, who-gets-what

Controllers/callbacks **never push directly**. Flow: domain event → create `Notification` row(s) → enqueue `DeliverPushJob(notification_id)`.

- **Assignment (C2, MVP):** fires only when `saved_change_to_assignee_id?` **AND** new assignee non-nil **AND** `assignee != actor`. One target, one deliberate action — no storm. Dedup absorbed by the `dedup_key` unique index.
- **Follow fan-out (C3, P2):** `NotifyTodoFollowersJob(todo_id, actor_id, change_kind)` diffs `saved_changes` against the **curated allowlist** (`status`, `assignee`, `due`, new comment) — never field typo-edits or no-op saves. Recipients = `(assignee ∪ followers) − actor`, deduped so assignee-who-also-follows gets one, filtered to users with active subscriptions. **Coalescing** is a separate windowed key (`todo_id + recipient_id + floor(now/window)`) or a debounced-drop-if-newer-pending job. Mirrors the `SyncAllOffersJob → SyncOffersJob` batch→per-target fan-out shape.
- **Deep-linking & shared read-state:** the `url` (e.g. `/todos/123#comment-456`) is carried in both the push payload and the in-app row; reading via *either* channel marks the *same* `Notification` row read.

### (c) German keyword/date extraction engine

- **Hand-rolled deterministic rule engine** (`GermanDateExtractor` service), **no NLP gem** (Chronic is English-only; Ruby German date libs are thin/unmaintained). A small grammar is testable against a golden corpus; an NLP dep is unbounded for negative-case testing.
- **Grammar (conservative, explicit only):** `am 5. Mai (um 14 Uhr)`, `am 05.05.`, `05.05.2026`, `morgen/übermorgen/heute`, weekday names (`nächsten Dienstag`), `um HH Uhr`, `HH:MM`. Trigger nouns (`Termin`, `Frist`, `Deadline`, `Treffen`) raise confidence / become the title. **Reject low-confidence; prefer a missed event over a junk one** (precision > recall).
- **Timezone (red line):** resolve through `Time.use_zone(Household.current.timezone)` **explicitly** — `households.timezone` defaults `"UTC"` (confirmed `db/schema.rb:92`), German installs set `Europe/Berlin`. Relying on global `config.time_zone` is a latent wrong-civil-day bug. Persist **UTC**.
- **Parser contract:** `{datetime, title, confidence, source_comment_id}` — **no character-offset bookkeeping** (XSS/off-by-one through ERB escaping). Standalone chip beneath the comment.
- **Auto-create vs confirm:** **suggest-then-confirm, always.** Runs as an `after_commit` job (never inline — the comment must be committed first). Confirm-to-create contains false positives *and* provides the structural loop-break (nothing generated without a click; the scan runs only on `source == "manual"` text).

### (d) Calendar UI — no Node build

- **Hand-rolled, server-rendered ERB**, not FullCalendar (red line). Rationale: FullCalendar's hardcoded theme won't flip under our token-override dark mode (`:root[data-theme="dark"]`), ships a 200KB+ bundle **not** in `PRECACHE_URLS` (so it breaks offline until first online load — verified `cacheFirst` is cache-on-first-use), and we model single-instance events with **no RRULE** so a recurrence engine is dead weight.
- **Views:** **month** = 7-col CSS Grid (~120 lines) reusing `.pill` geometry for `.cal-event` chips and existing tokens (dark-mode-correct for free); **agenda** = list; **day** = `grid-template-columns: 4rem 1fr` hour rows (cheap — included). **Scoped out:** week view, **event overlap/collision layout**, drag-create/resize (these are the genuinely hard parts).
- **Navigation:** `?date=` Turbo Frame links copying `meal_plan_path(date: …iso8601)` (`meal_plans/show.html.erb:6,13`). Stable `data-cal-day="YYYY-MM-DD"` hooks on cells/chips (DoD — de-risks QA's DST/month-boundary Cypress assertions; impossible with a black-box lib).
- **Todo due-date projection (C6a):** read-only chips over the existing Todo table — zero extraction, zero loop risk, distinct accent + legend. Delivers most of the "see my stuff on a calendar" value with no parser.
- **New components** (token-driven additions to `application.css`, never inline `style=""`): `.avatar`, `.toast`. `.modal/.sheet` deferred to when the event editor needs it. State-to-pill mapping fixed: `offen=.pill`, `in Arbeit=.pill.warn`, `erledigt=.pill.success`.

### (e) Bidirectional generation — loop/duplicate prevention

**Two structural layers + a human gate** (provenance alone is necessary but **not sufficient** — it's read *inside* the job, so without a guard every cascade hop still costs a Solid Queue row in the DB-backed queue sharing MySQL):

1. **Thread-local re-entrancy guard** — copy the confirmed `GroceryItem.without_bring_sync` (`Thread.current[:pantria_skip_bring_sync]`, `app/models/grocery_item.rb:50-59`) as `CalendarEvent.without_extraction` / `Todo.without_extraction`. Wrap every auto-generation write so the `after_commit` echo is suppressed **at source, before `perform_later`**.
2. **Provenance enum gates scan-eligibility** — `source != "manual"` is **never** re-scanned and **never** renders a suggestion chip (the visible UI contract). One-hop, no-chaining: a `comment_extraction` event never spawns a todo; a `calendar_extraction` todo never spawns an event.
3. **Human-confirm gate** — nothing is generated without a click, so even an accidental chain can't run unattended.

**Dedup on provenance** (`source_record`), not content-hash. Extractor jobs `find_or_create_by`/`upsert` + `rescue RecordNotUnique`. Migration with provenance + guards lands **before** any generation code.

---

## 5. Phased Delivery Plan

> PR order is a hard sequence where dependencies exist. **Phase 1 ships value with zero new infra.**

### Phase 0 — Cable transport (prerequisite, only when live broadcast is wanted)
- **Scope:** Add `gem solid_cable` (DB-backed, no new container, consistent with the Solid Queue/Cache trinity for a self-hosted box). Switch `config/cable.yml` production from `adapter: redis` to `solid_cable`.
- **Owner:** Tech Lead / Infra · **Complexity:** S
- **Exit:** A trivial Turbo Stream broadcast boots in production. *Not required for Phases 1–3* (bell renders on navigation).

### Phase 1 — Todo + 3 states + comments (C1, C4) — **shippable on its own**
- **Scope:** `Todo` model (fixed `STATES`, guarded transitions, `completed_at`), `TodoPolicy` (member CRUD, admin destroy), list grouped by state with one-tap in-place next-state pill (Turbo Stream replace), `TodoComment` with Turbo Frame append. `.avatar` component (email-first identity chain). Plain server-rendered CRUD — **no broadcast, no push**.
- **Owners:** Tech Lead (models/policy), UX/UI (list + pill + avatar), Architect (state model)
- **Complexity:** M
- **Exit:** Member creates → moves through 3 states → comments → completes; actor sees own change instantly via Turbo Frame; full NxN transition matrix spec (incl. illegal + no-op self-transition = zero side effects); de+en parity spec green.

### Phase 2 — Notification ledger + assignment + follow data (C2 data, C3 data)
- **Scope:** `Notification` ledger (`dedup_key` unique index, polymorphic, `url`, `read_at`); top-nav bell rendering rows **on navigation**; `assignee_id` column + fixed avatar/toggle row over `Household.current.users`; `TodoFollow` join (auto-follow on assignment, opt-in on comment); follow bell **drives a real in-app notification** (non-lying). No push delivery yet.
- **Owners:** Architect (ledger), Tech Lead (assignment/follow), UX (bell + deep-link contract)
- **Complexity:** M
- **Exit:** Assigning creates a `Notification`; bell shows it; following produces a real row; no-op save + self-assignment produce zero notifications.

### Phase 3 — Web Push infrastructure + assignment push (C2 delivery) — **XL**
- **Scope:** `web-push` gem, VAPID keypair, `PushSubscription` (unique on `endpoint_digest`), service-worker `push`/`notificationclick` handlers, `push_subscribe_controller.js` with soft pre-ask + visible degradation recovery states, `DeliverPushJob` (Solid Queue, 410/404 prune), `UserMailer` fallback. Wire assignment `Notification` → `DeliverPushJob`.
- **Owners:** Architect + Tech Lead (push stack), PWA owner (SW), UX/UI (permission UX), Security (VAPID in ENV)
- **Complexity:** XL
- **Exit:** Assignee on installed Android PWA gets the push, `notificationclick` opens the deep-link; webmock'd 410 prunes exactly that row and doesn't retry forever; no-subscription → zero send; each degradation branch shows a localized recovery banner. **The Todo MVP (Phases 1–2) ships and is useful even if this never works on a device.**

### Phase 4 — Calendar display + todo due-projection (C6a)
- **Scope:** `CalendarEvent` model, server-rendered month + agenda + simple day view (ERB, `?date=` Turbo Frame nav, `data-cal-day` hooks), todo `due_on`/`due_at` projected read-only.
- **Owners:** UI (grid/CSS), Tech Lead (model/controller)
- **Complexity:** L (excl. overlap/drag, which are out)
- **Exit:** Events + todo dues render in correct cells across month-boundary and DST (Cypress DE @360px); ellipsis + "+N weitere" overflow assert; this answers "is the calendar wanted" affirmatively with no NLP.

### Phase 5 — Follow fan-out (C3 push)
- **Scope:** `NotifyTodoFollowersJob` with curated change-allowlist (diffed from `saved_changes`), actor self-suppression, assignee/follower dedup, per-follower subscription filtering, **windowed coalescing** (separate from the unique index).
- **Owners:** Tech Lead + Architect (jobs), QA (storm specs)
- **Complexity:** M
- **Exit:** N followers incl. actor → N−1 deliveries; 5 edits in 2s → ≤1 per follower; no-op/typo-fix → zero. *(QA gates the merge.)*

### Phase 6 — German extraction → calendar suggestion (C5)
- **Scope:** `GermanDateExtractor` + golden corpus (negative cases + DST boundaries, written **first**), `ExtractCalendarEventsJob` (after-commit, suggestion only), standalone chip, `SuggestionDismissal` persistence, parametrized-timezone contract.
- **Owners:** Parser owner / Tech Lead, QA (corpus), UX (chip lifecycle)
- **Complexity:** L
- **Exit:** Corpus passes (incl. negatives "5 Äpfel"/"Seite 14" → no chip, ambiguous → no chip); 14 Uhr Berlin → 13:00 UTC winter; dismissed chip never re-nags; confirm creates `CalendarEvent(source: "comment_extraction")`.

### Phase 7 — Bidirectional loop + event→todo (C7) — **later**
- **Scope:** Provenance enum + `without_extraction` guards landed in migration before code; C7 event→todo suggestion (one-hop, human-confirmed).
- **Owners:** Architect (guard/provenance), QA (loop-bound spec)
- **Complexity:** L
- **Exit:** comment→event→todo cascade settles in **asserted exact** job + row counts; re-save of a generated record → zero new extraction enqueues; concurrent retry skips via `rescue RecordNotUnique` (no 500).

---

## 6. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| **iOS Web Push** only works for installed PWAs (16.4+), silently no-ops otherwise | Subset of members get no push | In-app Notification ledger + bell is the reliable baseline; feature-detect + "zum Home-Bildschirm hinzufügen" hint; `UserMailer` fallback; Todo MVP never blocks on push |
| **Cold permission prompt** → permanent per-origin denial | Push dead on arrival | Never on-load; user-gesture soft pre-ask only |
| **German date false positives** (auto-create junk: "5 Äpfel", "Seite 14") | Trust erosion | Suggest-then-confirm (no auto-create) + golden corpus with negative cases + confidence gating |
| **Timezone wrong-civil-day** (parse in UTC not household tz around DST) | Missed Termin, looks broken | `Time.use_zone(Household.current.timezone)` explicitly; `households.timezone` defaults UTC (not Berlin); specs parametrized over both; store UTC |
| **C5↔C7 infinite enqueue loop** (repo already drives jobs from `after_*_commit`) | Solid Queue table fills, hard to kill | `without_extraction` thread-local guard (suppress at source) + provenance gate + human-confirm; loop-bound spec asserts exact counts |
| **C3 notification storm** ("notify on ANY change" + auto-follow-on-comment) | Members disable all notifications, poisoning the valuable assignment push | Curated change-allowlist + actor self-suppression + dedup + coalescing; follow-on-comment opt-in |
| **Dead/duplicate PushSubscriptions** (endpoint rotation, re-install) | Retry-storm against 410 endpoints; duplicate pushes | Unique index on `SHA256(endpoint)`; prune on 410/404 in first delivery impl |
| **MySQL 8.4 index failure** on raw endpoint (utf8mb4 3072-byte prefix) | Schema-load failure | Unique index on `endpoint_digest`, mirroring `api_tokens.token_digest` |
| **Live broadcast vaporware** (cable = redis, no gem, zero usage) | "Push is optional because Turbo" doesn't boot | MVP bell renders on navigation (no Cable); `solid_cable` is an explicit Phase 0 increment |
| **FullCalendar dark-mode clash + offline gap** | Bright-white calendar, breaks offline | Hand-rolled ERB grid (token-driven, on-brand, rides existing networkFirst HTML path) |
| **German text overflow at 360px** | Visual breakage | First-class constraint: short state labels, 2-letter weekday abbrevs, ellipsis+`title=`, "+N weitere", flex-wrap avatars |
| **Real push e2e flakiness** | Perpetually-skipped CI spec | Layered tests (RSpec+webmock for job, Cypress for UI branches); delivered-push = manual on-device |

---

## 7. Test Strategy

**General DoD per slice:** de+en i18n parity (no-missing-keys spec across new namespaces + one DE Cypress run asserting German labels render via `?locale=en`/`?locale=de`); all times stored UTC / rendered `Household.current.timezone`; never naive `Time.now`.

| Phase | RSpec / FactoryBot | Cypress | Notes |
|---|---|---|---|
| **1 (C1/C4)** | Exhaustive NxN transition matrix (illegal + no-op self-transition → zero side effects); `TodoPolicy`; comment model | List render, one-tap pill replaces row in place (no reflow), comment append | meal_plans ERB+Turbo idiom |
| **2 (ledger/assign/follow)** | `Notification` `dedup_key` uniqueness (two enqueues same event → one row); assignment guard (no-op save + self-assign → zero); follow drives a row | Bell shows row on navigation; deep-link anchor | Idempotency ≠ coalescing |
| **3 (push)** | `DeliverPushJob` VAPID request shape (**webmock**, confirmed in Gemfile.lock); 410/404 prunes exactly that row, no retry-storm; `PushSubscriptions#create` request spec; no-sub → zero send | Permission button render; denied/iOS-not-installed/unsupported recovery banners (stub `window.Notification`/`navigator.serviceWorker`) | **Real delivered notification = manual on-device only** (untestable in headless CI) |
| **4 (calendar)** | Event scoping, due-projection query | Event in correct cell across month-boundary **and** spring-forward DST day (via `data-cal-day`); ellipsis no-h-scroll; "+N weitere" @360px DE | Stable hooks = library-independent |
| **5 (C3 fan-out)** | N followers incl. actor → N−1; 5 edits in 2s → ≤1/follower; allowlist filtering; per-follower subscription respect | — | QA blocks merge if only a unique index ships |
| **6 (C5)** | **Golden corpus IS the spec** (written first): positives, negatives, ambiguous→nil, DST boundaries; parametrized over UTC + Berlin; dismissal persistence | Chip appears/dismisses/never re-nags | `Time.use_zone` explicit |
| **7 (C7/loop)** | `perform_enqueued_jobs` asserts **exact** job + row counts on comment→event→todo cascade; re-save → zero new enqueues; concurrent retry skips via `rescue RecordNotUnique` | — | Guard + provenance proven by spec, not convention |

---

## 8. Open Questions for the Product Owner

1. **iOS support expectation.** What's the device reality for this household? If everyone is on Android-installed-PWA, push is high-value. If iOS users exist, the in-app bell + `UserMailer` carry more weight and push priority could drop below the calendar. *(This swings the Phase 3 vs Phase 4 ordering.)*
2. **Calendar value source.** Confirm: is C6 wanted **for its own sake**, or only as a destination for extracted dates? We've split it so **C6a (display + todo-due projection)** answers this affirmatively with zero NLP — if that satisfies the real need, C5/C7 may defer indefinitely. **Do you want C5 at all once C6a ships?**
3. **C3 follow granularity.** We're proposing the curated allowlist (`status`, `assignee`, `due`, new comment) over the verbatim "ANY change." Confirm this is acceptable, and **give the coalescing window number** (e.g. "≤1 per follower per 60s") — QA cannot write the storm-prevention DoD without it.
4. **Confirm-to-create is permanent?** We're asserting suggest-then-confirm in every phase (never silent auto-create). Confirm you don't ever want fully-automatic event/todo creation — it changes the UX feel and re-introduces the loop/false-positive risk.
5. **State set fixed at three.** Confirm `offen / in Arbeit / erledigt` only, with `archiviert` as a visibility flag (not a status) and `abgebrochen/canceled` deferred. **No admin-editable states** unless explicitly requested.
6. **Keyword configurability.** The German trigger vocabulary (`Termin`, `Frist`, `Deadline`, …) is **code**, not a user-editable table. Confirm the household doesn't need to edit triggers themselves (would significantly raise C5 scope).
7. **`UserMailer` fallback scope.** Is email an acceptable permanent fallback when a user has no push subscription, or is push the only intended channel? This decides how much the email path matters.
8. **Live in-app updates.** Do you want the bell/toast to update **live** (requires the Phase 0 `solid_cable` increment) or is **on-next-navigation** acceptable for v1? The latter ships with zero new infra.
