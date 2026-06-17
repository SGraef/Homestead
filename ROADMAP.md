# Homestead Roadmap — Beta → 1.0

> **Renaming in progress:** this project is **Pantria → Homestead**. The product
> outgrew "pantry + shopping"; the new name and positioning match what it has
> become. The mechanical rename is scheduled as milestone **H0** below — until it
> lands, the code, repo and images still say *Pantria*.

> **Status:** Working plan, re-baselined against the shipped codebase (June 2026).
> **Tagline:** *Run your home from one place.*
> **Theme:** *One household, self-hosted — earn trust, then deepen the home.*

---

## 1. What Homestead is now

**Homestead is a self-hosted operations hub for a single household.** One
deployment serves exactly one home; everyone in the household shares one set of
data. It started as a pantry/grocery tracker and has grown into the place a
family runs the practical side of the house from:

- **Inventory** — pantry / fridge / freezer / cellar / custom locations, expiry
  warnings, "used N" decrement, scan-to-add kiosk.
- **Shopping** — shared grocery list (freeform or product-linked), two-way
  **Bring!** sync, mark-purchased-by-barcode.
- **Receipts & prices** — JPEG/PNG/HEIC/PDF upload, Tesseract OCR + heuristic
  parser → Stores/Products/Prices, inbound IMAP e-receipt polling, a multi-store
  price history and an expenses view.
- **Offers** — daily multi-retailer feeds (Marktguru/kaufDA/MeinProspekt/
  Flaschenpost), per-household allow-list, categories, watchlist, blocklist.
- **Recipes & meal plan** — Chefkoch import, ingredient "used" → storage
  decrement, weekly suggester with soft DGE guidelines.
- **Collaboration** *(new)* — shared **todos** (three states, assignment,
  follow, comments), a first-class **notification** ledger with a top-nav bell,
  **PWA Web Push**, an in-app **calendar** (month/agenda/day + todo-due
  projection + German date detection), and **two-way Google Calendar sync**.
- **Multi-user** — admin/member roles, closed registration after first run,
  **tokened invite links** for additional members.
- **Platform** — installable PWA + Android TWA, REST API for automation,
  opt-in OpenTelemetry, MkDocs documentation site.

### The architectural keystone: single household per instance

Homestead serves **one household per deployment** (`Household.current`; the first
sign-up creates it, registration then closes, members are added by invite). This
is deliberate and load-bearing:

- **No cross-tenant boundary to defend.** There is no "switch household", no
  per-request tenant resolution, no `X-Household-Id`. The entire class of
  cross-tenant data-leak risk — previously the project's #1 critical risk — is
  **designed out**, not merely tested against.
- **Authz simplifies to membership + role.** Every authenticated member sees all
  household data; `admin` governs settings, member management and destructive
  deletes. Pundit policies no longer carry a scoping burden.
- **What still applies:** relational integrity *within* the household
  (`Price ↔ store`, `RecipeIngredient ↔ product`, calendar-event provenance) and
  a safe, non-destructive upgrade path. Those are not tenancy concerns and stay.

Everything below is framed by this: we are deepening **one** home, not scaling a
multi-tenant SaaS.

---

## 2. Guiding principles

1. **One household, fully trusted internally.** Single-household-per-instance is
   the invariant. We do not add tenant-scoping machinery; we add value inside the
   one household. Relational integrity and a safe upgrade path replace tenant
   isolation as the load-bearing correctness concerns.
2. **No destructive upgrades, ever.** A green migration on an empty DB proves
   nothing. The upgrade path is "done" only when proven against a prior-release
   seed **with resolvable Active Storage blobs** and integrity assertions. No
   migration-bearing feature ships ahead of it. *(Now more urgent — the schema
   has grown to todos, notifications, calendar and sync tables.)*
3. **Gates enforce, not observe.** RuboCop is already blocking (M0). Sorbet
   flips to blocking per the spike; a coverage floor lands. Decorative CI on
   LLM-authored, security-sensitive code is unacceptable.
4. **Internet-exposed is the assumed posture.** The household runs Homestead
   behind public TLS, so brute-force, session/CSRF, SSRF and abuse are in the
   threat model — not just data-at-rest. Security work is sized for that.
5. **Proactive over passive.** The home should *tell you* what needs attention
   (something expiring, low stock, a watched item on offer, a chore due) — the
   notification + push stack now exists to make that real. A hub you have to
   remember to open is a worse hub.
6. **Finish before you start; schema-free UX runs in parallel.** The last 20% of
   advertised features (offer images, OCR trust, feed health) outranks net-new
   modules. Mobile-first UX work touches zero models and ships alongside hardening.
7. **Never ship the signal-less version of a data-corrupting action.** "Accept
   all auto-matched" waits on per-line OCR confidence; live broadcasts ride the
   job-safe echo guard and the defined Bring! conflict policy.

---

## 3. Delivered since the last roadmap ✅

Re-baseline — these were planned items (or net-new) and are now **shipped**:

| Delivered | Notes |
|---|---|
| **Single-household collapse** (#9) | `Household.current`; closed registration; invite-based members. Retired the cross-tenant fuzz-matrix and `Current.household` retrofit entirely. |
| **Collaborative Todos + Notifications + Web Push** (#11) | Three states, assignment, follow, comments; first-class `Notification` ledger + bell; full VAPID Web Push stack (`web-push`, `DeliverPushJob`, 410/404 prune). |
| **In-app Calendar + German date extraction** (#11) | Server-rendered month/agenda/day, read-only todo-due projection, suggest-then-confirm comment→event and event→todo. |
| **Two-way Google Calendar sync** (#12) | One connection per instance, admin-only OAuth, 5-min incremental poll + push-on-change, `sync_origin`/`remote_id`/`etag` echo guard. |
| **Tokened household invites** | `Invitation` (digest at rest), `invitations`/`activations` flow. *(Was M2 — done.)* |
| **M0 security & CI quick wins** *(PR open)* | Bring! tokens encrypted at rest; ImageMagick upload pipeline hardened (env/`-limit` + magic-byte allowlist; `policy.xml` is inert in our IM6 build); RuboCop **blocking** via `.rubocop_todo.yml`; SimpleCov print; `srb tc` baseline (~464). |
| **OpenTelemetry instrumentation** (#5) | Opt-in SDK + exporters wired; per-job/per-source emission still to be fully connected (see H1). |
| **`solid_cable`** in the stack | DB-backed Action Cable is present — the live-sync prerequisite is **met** (no Redis needed). |
| **Docs site + feature docs** | MkDocs Material site; Todos/Calendar/Calendar-sync pages + OAuth guide *(PR open)*. |

**Recorded product decisions (M0):** deployment posture = **internet-exposed
behind TLS**; Bring! conflict policy = **union, Bring! wins ties** (absence =
"not yet synced", never a silent delete).

---

## 4. Roadmap by milestone

Effort key: **S** ≤ ~2 days · **M** ≤ ~1 week · **L** ≤ ~2–3 weeks · **XL** multi-sprint.
Milestones renumbered for the Homestead era (H-series).

### H0 — Rebrand: Pantria → Homestead
**Goal:** Adopt the new name with minimal churn and zero data risk. Mostly
independent of the other tracks; do the cheap user-facing parts now (pre-1.0,
~0 users — cheapest it will ever be), defer the expensive internal churn.

| Initiative | Owner | Pri | Effort |
|---|---|---|---|
| **User-facing rename** — `app_name` i18n key (de+en), the few hardcoded "Pantria" strings (service-worker push default, sign-in title), manifest `name`/`short_name`, theme/wordmark SVGs, README + docs site title | UI + Dev | P0 | S |
| **External identifiers** — repo `SGraef/Pantria` → `Homestead` (GitHub keeps redirects); Docker image `ghcr.io/sgraef/pantria` → `…/homestead`, **dual-publish the old tag for one release** so existing pulls don't break; docs domain | Dev/Infra | P0 | S |
| **Android TWA** — package `de.lunawolf.pantria` → `…homestead`, re-register `assetlinks` fingerprints (new Play identity — fine pre-release) | PWA | P1 | S |
| **Config defaults** — default DB names `pantria_*` → `homestead_*` (env-overridable, so existing prod DBs keep their name), compose/CI env, ENV-var prefixes | Dev | P1 | S |
| **Internal Ruby module `Pantria`** — rename to `Homestead` **(deferred / optional)**: high churn (every `Pantria::` ref, app constant, eager-load paths) for cosmetic gain. Only if/when a quieter release window opens. | Architect | P3 | M |

**Exit criteria:** every user-visible surface says Homestead; image + repo
redirect cleanly with a one-release bridge tag; no data migration required;
internal module rename explicitly logged as deferred tech-debt.

#### M0 — Status & recorded decisions (✅ delivered)

**Product decisions (PO):**
- **Deployment posture → internet-exposed behind TLS.** Pantria runs on the public internet behind an HTTPS reverse proxy. The threat model therefore includes brute-force, session/CSRF, and exposed-endpoint abuse on top of data-at-rest. **Consequences:** the M1 SSRF allowlist + private-IP redirect block stays required (it was already posture-independent); **bearer-token rate-limiting is now in-scope for M1** (the `default_household` row in M1 made it posture-conditional — it is now ON); IMAP-TLS enforcement stays in scope.
- **Bring! conflict policy → union, Bring! wins ties.** On divergence, merge both sides (keep every item present in either system); when the *same* item conflicts (e.g. checked-state differs), the Bring! app's state wins. No silent deletes from a missing-on-one-side item — absence is treated as "not yet synced", not "delete". This is what the M2 Bring! conflict/dedup/race matrix and the M3 live-sync gate are written against.
- **Success metrics** (emitted via OTel to steer M3 sequencing): time-to-first-storage-item, scans/week, receipts confirmed-vs-discarded, members-per-household, concurrent-edit rate.

**Engineering quick wins (delivered):**
- **Bring! tokens encrypted at rest** — `encrypts :access_token, :refresh_token`; migration widened columns to `text` and cleared plaintext (benign re-auth). Spec asserts ciphertext ≠ plaintext in the DB.
- **Upload-pipeline hardening** — our Debian reproducible-build ImageMagick 6 **silently ignores `policy.xml`** (verified: malformed XML raises no parse error; coder/limit rules never apply). Enforced controls instead: resource/DoS limits via `MAGICK_*_LIMIT` env vars + per-`convert` `-limit` flags; coder-RCE (ImageTragick) blocked by an application-layer magic-byte raster allowlist that keeps script files away from `convert`. `policy.xml` still shipped as best-effort defense-in-depth.
- **CI ratchet part 1** — RuboCop **blocking** with `.rubocop_todo.yml` grandfathering 13 pre-existing offenses (zero LineLength/TrailingComma debt — those were fixed outright); non-gating SimpleCov line-coverage print on the RSpec job; `srb tc` baseline captured: **~464 errors**, almost all Rails-DSL "method does not exist" pending tapioca RBIs (sizes the M1 Sorbet flip — RBIs are a prerequisite, not a quick toggle).

---

### H1 — Trust & Operability (hardening core)
**Goal:** Make Homestead safe to upgrade and safe to expose. *Nothing here is
user-visible — that is the point.* Runs concurrently with the H1-UX track.
**Removed from the old plan:** cross-tenant fuzz matrix and `Current.household`
retrofit (obsoleted by single-household).

| Initiative | Owner | Pri | Effort |
|---|---|---|---|
| **Upgrade & data-migration path** — versioned GHCR releases, automated pre-upgrade DB + Active Storage backup, `rails homestead:upgrade` with rollback, **N-1 migration smoke test against a prior-release seed with resolvable blobs**; integrity assertions (household intact, attachments resolvable, no orphaned receipt/price/calendar rows). **One** shared fixture, delivery + QA. | Architect/Dev + QA | P0 | L |
| **SSRF host-allowlist across the 6 outbound fetchers** (marktguru/kaufda/mein_prospekt/flaschenpost/chefkoch/barcode_lookup) + block redirects to private IPs + Google Calendar/Push egress review + **IMAP TLS verification policy** — posture is internet-exposed, so this is **required**, not posture-gated | Architect/Dev | P0 | M |
| **Bearer-token + auth rate-limiting** (`rack-attack` — none today) — login, password-reset, API tokens, invite-activation, push-subscribe endpoints; posture is internet-exposed | Architect | P0 | M |
| **CI ratchet part 2** — flip Sorbet to blocking per the M0 spike (tapioca RBIs for the Rails DSLs are the real prerequisite, not a toggle); `typed: strict` on security/money/parser files first (`BringConnection`, `CalendarConnection`, `ImapPoller`, `Price`, receipt parser, push delivery); fixed `minimum_coverage` floor (baseline − ~2%) | Dev/QA | P1 | M |
| **Promote in-app FK-consistency checks to DB constraints** (`Price`, `RecipeIngredient`, `MealPlanEntry`, `StorageItem`, `CalendarEvent` provenance) | Architect | P1 | M |
| **Wire OTel into the silent jobs** — Bring 5-min pull, IMAP poll, daily offers, **calendar poll/push**, push delivery — with job-failure surfacing and per-source health | Architect | P1 | M |
| **i18n parity guard** — `i18n-tasks` CI step failing on missing/unused keys (de vs en), now spanning the new todo/calendar/notification namespaces | QA | P2 | S |
| **Web Push / Calendar secret hygiene** — VAPID + Google OAuth secrets documented for rotation; encrypted-attributes-at-rest policy extended to all token columns | Architect | P1 | S |

**Exit criteria:** upgrade smoke test green on a blob-bearing prior-release seed;
SSRF allowlist + private-IP block live on all fetchers and the calendar egress;
auth endpoints rate-limited; RuboCop **and** Sorbet blocking with a coverage
floor; OTel surfaces every recurring job's health; de/en parity enforced.

---

### H1-UX — Mobile-First Foundation (parallel to H1)
**Goal:** Fix the "feels like a website" gap. Touches zero models/migrations, so
it runs alongside hardening. **Updated:** the navigation IA must now also surface
the new Todos and Calendar.

| Initiative | Owner | Pri | Effort |
|---|---|---|---|
| **SVG icon sprite** (inline, `currentColor`-themeable) replacing emoji — prerequisite for the bottom nav | UI | P0 | M |
| **Bottom tab bar + overflow drawer** — UX owns IA (the primary set now must choose among Storage, Grocery, Scan, Todos, Calendar, Offers — "More" holds the rest); UI owns geometry, `safe-area-inset`, German worst-case labels, active-state wiring | UX + UI | P0 | L |
| **Branded empty/placeholder primitives** — height-stable placeholder tile, status badge, empty-state block; **start with offer cards** (never render collapsed), extend to the new todo/calendar empty states | UI | P0 | M |
| **Dark-mode pill/chip contrast fix** — `.pill.warn/success/danger` dark-on-dark fails AA; also covers the new todo-state pills | UI | P1 | S |

**Exit criteria:** no emoji in primary nav/controls; installed PWA/TWA shows a
native-feel bottom tab bar respecting the notch; offer/todo/calendar surfaces
render branded placeholders; status pills pass WCAG AA in dark mode. **Gate:**
any CSS/component change ships its Cypress light+dark × mobile+desktop
visual-regression baseline in the same PR.

---

### H2 — Finish the Features (core-loop polish)
**Goal:** Close the last 20% of the food/shopping loop, now safely on the tested
schema. **Removed:** invites (shipped).

| Initiative | Owner | Pri | Effort |
|---|---|---|---|
| **Marktguru `image_url` derivation** (`offers.rb` hardcoded `nil`) + designed placeholder contract; ships behind a golden fixture | Dev + UI | P1 | S |
| **Per-line OCR confidence scoring** (backend) — no `confidence` field today; hard prerequisite for any bulk confirm | Dev | P1 | M |
| **Receipt-confirm UX** — mobile line-cards, collapse-on-resolve, sticky confirmed-count; ships first (no backend dep); **"accept all auto-matched" held until confidence lands** | UX | P1 | L |
| **Bring! sync correctness** — replace the cross-process-unsafe `Thread.current` skip flag with the **`sync_origin` DB-column pattern the calendar already uses**; then the **conflict/dedup/race test matrix** against the M0 policy (union, Bring! wins ties) | Dev/Architect + QA | P1 | M |
| **Receipt OCR golden-file harness** + parser-version stamping (idempotent re-parse); synthesized German-retailer corpus, real anonymized receipts as opt-in donation | QA | P1 | M |
| **Integration hardening** — VCR-style contract fixtures per feed/import; per-source health/staleness (generalize `ImapPoller.last_polled_at`/`last_error` across offer feeds + calendar sync); retry/backoff so one dead feed doesn't fail `sync_all_offers_job`; OTel-wired alerting | Dev | P1 | L |
| **Honest empty/error/loading states** — live pending-receipt status (Turbo, not a refresh link), Bring!/IMAP/Calendar health badges, low-confidence-line callout | UX + UI | P1 | M |

**Exit criteria:** offer cards show real images (placeholder on failure);
receipts carry per-line confidence + a glanceable mobile confirm flow with
bulk-accept only on matched/high-confidence lines; Bring! has a job-safe echo
guard and a tested conflict matrix; every external feed degrades gracefully with
visible per-source health.

---

### H3 — Deepen the Home (household-OS expansion)
**Goal:** Build on the collaboration stack (todos, push, calendar, `solid_cable`)
to make Homestead proactive and genuinely the place the household runs from.
**Metrics-aware:** the heavier bets are gated on OTel activation signals.

| Initiative | Owner | Pri | Effort |
|---|---|---|---|
| **Proactive reminders engine** *(flagship)* — extend the existing `Notification` ledger + `DeliverPushJob` to fire on real household signals: **expiry** (storage already has dates), **low-stock / restock** (depletion + price history + active offers), **offer-watchlist hits**, **calendar/todo due**. One opt-in, per-type, quiet-hours-aware. Reuses push + the bell; no new transport. | Architect + UX | P1 | L |
| **Live Turbo Stream sync** (grocery, storage, todos, notification bell) — **infra now ready (`solid_cable`)**; gated only on (a) the job-safe Bring/calendar echo guard, (b) a per-household stream channel + auth test, (c) OTel confirming concurrent multi-member editing. *(Isolation gate removed — single household.)* | UX + Dev | P2 | M |
| **Recurring chores** — recurrence (RRULE-lite) on todos + assignment **rotation** among members + read-only calendar projection + push on due. Natural extension of todos+calendar+push. | Dev + UX | P2 | M |
| **Spend & budget analytics** — promote the expenses view into a real dashboard: spend by store/category/month, trends, basket cost over time (reuses receipts + the multi-store price history). Optional budget targets with push when exceeded. | Dev + UX | P2 | M |
| **Document & warranty vault** — Active-Storage-backed home documents (warranties, manuals, insurance) with **expiry/renewal reminders** projected onto the calendar + push. | Dev + UX | P2 | M |
| **Guided first-run onboarding** — create household → scan/import first item → invite a member → enable push; tied to activation metrics. | PO + UX | P2 | M |
| **iCal export feed** — read-only `.ics` of the household calendar for non-Google clients (complements the two-way Google sync). | Dev | P3 | S |
| **Home Assistant / webhook bridge** — outbound events (low stock, expiry, offer hit) + an inbound quick-add webhook; a self-hoster delight that turns Homestead into a home-automation signal source. | Dev | P3 | M |
| **Pantry-aware "cook now"** — rank recipes by what current storage can actually make; nudge meal-plan choices toward expiring stock. | Dev | P3 | M |
| **AI meal-suggester** — **still frozen** until core-loop activation metrics justify it. | PO | P3 | — |

**Exit criteria:** the proactive reminders engine ships behind a clean opt-in and
measurably surfaces expiries/offers before they're missed; live sync (if metrics
justify) is household-channel-scoped with an auth test and rides the echo guard;
at least one of {recurring chores, spend analytics, document vault} ships as the
first "beyond food" pillar; onboarding reduces cold-start drop-off.

---

## 5. New-feature thesis (why these, what they reuse)

The collaboration work (#11/#12) changed what Homestead *can* be. The strongest
new features are the ones that compound on infrastructure that already exists:

- **Push + Notification ledger** → the **proactive reminders engine** (expiry,
  low-stock, offer hits, due dates). Highest leverage: the home starts working
  *for* you, and it reuses a stack that's already built and tested.
- **Calendar** → the household's single timeline: meal plan, chores, expiries,
  warranty renewals, bills — all projected into one place. iCal export and
  recurring chores extend it cheaply.
- **`solid_cable`** → **live sync** with no new infrastructure; the only blockers
  are correctness (echo guard) and proof of demand (metrics).
- **Receipts + multi-store prices** → **spend & budget analytics**; the data is
  already captured, it just isn't surfaced as insight yet.
- **Active Storage** → the **document/warranty vault**; reuses the same
  attachment plumbing receipts already ride.
- **OTel** → tells us *which* of these to build next, instead of guessing.

Curated priority: **proactive reminders** first (reuses the most, delivers the
most), then **live sync** + **recurring chores** (collaboration depth), then
**spend analytics** + **document vault** (the first true "beyond food" pillars),
with **webhooks / Home Assistant** and **cook-now** as self-hoster delight.

---

## 6. Cross-cutting workstreams

- **Quality / CI gates.** RuboCop blocking (done, M0) → Sorbet blocking + `typed: strict` on security/money/parser files first (H1) → fixed coverage floor (H1). Cypress visual-regression (light/dark × mobile/desktop) is a hard prerequisite in the same PR as any CSS change. i18n parity guard in CI.
- **Security.** Internet-exposed posture: in-process SSRF allowlist + private-IP redirect block on all fetchers **and** the calendar egress (required); `rack-attack` rate-limiting on auth/API/invite/push endpoints; encrypted-attributes-at-rest for every token column (Bring, Google OAuth); invite tokens remain an auth boundary.
- **Observability.** Wire opt-in OTel into every recurring job (Bring, IMAP, offers, calendar poll/push, push delivery) with failure surfacing + per-source health; emit activation metrics to steer H3.
- **Data-migration / upgrade path.** One shared prior-release seed with resolvable blobs, co-owned by delivery + QA; versioned tags, automated backup/rollback, integrity assertions. Hard gate on all migration-bearing features — and the schema is bigger now (todos, notifications, calendar, sync, invites).
- **Design system.** Icon sprite → bottom nav (incl. Todos/Calendar) → empty-state/badge primitives → incremental utility layer → docs page. Validated against worst-case German strings and dark-mode AA.
- **Rebrand (H0).** User-facing + external identifiers now; internal module rename deferred.

---

## 7. Sequencing & dependencies

```
Single-household (DONE) ──────────► tenancy work retired (no fuzz matrix, no Current.household)
M0 hardening (DONE) ──────────────► Sorbet ratchet pt.2 (H1) needs the srb-tc baseline
M0 Bring conflict policy (DONE) ──► Bring job-safe guard + conflict matrix (H2) ──► live sync (H3)

Upgrade smoke test green (H1) ────► ANY migration-bearing feature
                                     (OCR confidence, chores, vault, analytics) (H2/H3)

SSRF allowlist + rate-limit (H1) ─► safe to stay internet-exposed

Icon sprite (H1-UX) ──────────────► bottom tab bar (H1-UX) ──► non-color a11y (H3)
Per-line confidence (H2) ─────────► "accept all auto-matched" bulk action (H2)
Bring sync_origin guard (H2) ─────► live sync (H3)
solid_cable (DONE) ───────────────► live sync infra ready (H3)
Notification ledger + push (DONE) ► proactive reminders engine (H3)
Calendar (DONE) ──────────────────► recurring chores / vault reminders / iCal export (H3)
Visual-regression baseline ───────► any CSS/component refactor (same PR)
```

**Why these orderings:**
- **Upgrade harness gates schema churn.** Every H2/H3 feature that adds columns
  (OCR confidence, recurrence, documents, budgets) is exactly what bricks
  self-hoster data without a tested N-1 path — and there's more schema to protect
  now than when this gate was first written.
- **Live sync is a correctness feature, not a UI one.** `turbo_stream_from`
  bypasses Pundit; a guessable channel leaks live edits even within one
  household, and it fires from background Bring/calendar jobs where a bad echo
  guard amplifies duplicates. Gated on the job-safe guard + a channel-auth test +
  metrics. (The old cross-tenant isolation gate is gone.)
- **Confidence gates bulk-accept.** "Accept all matched" without a confidence
  signal mass-confirms bad OCR into Products/Prices, corrupting the multi-store
  pricing differentiator.
- **Reminders before more modules.** The push stack is built but barely used;
  pointing it at expiries/offers/dues is the cheapest large win available and
  proves the proactive thesis before investing in heavier H3 pillars.

---

## 8. Key risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Destructive upgrade** wipes pantry/receipt/price/calendar history — no tested path, ~48 migrations now | Critical | Versioned releases + automated backup/rollback + N-1 smoke test on a blob-bearing prior-release seed (H1); hard gate on migration-bearing features |
| **SSRF / image-decoder RCE** via 6 outbound fetchers + HEIC/PDF pipeline + calendar egress | High | App-layer magic-byte allowlist + `-limit`/env caps shipped (M0); in-process host-allowlist + private-IP redirect block on all fetchers (H1) |
| **Internet-exposed with no rate-limiting** — brute-force on login/reset/API/invite | High | `rack-attack` on all auth/API/invite/push endpoints (H1) |
| **Silent quality rot** on LLM-authored code | High | RuboCop blocking (done); Sorbet blocking + `typed: strict` on highest-risk files + coverage floor (H1) |
| **Bring! sync loss/duplication** — process-local skip flag fails across Solid Queue workers | High | Adopt the calendar's `sync_origin` DB-column guard for Bring + conflict matrix against the M0 policy (H2); block live sync until both land |
| **Secret sprawl** — Bring, Google OAuth, VAPID keys; rotation invalidates subscriptions/connections | Medium | Encrypted-at-rest for all token columns; documented rotation runbooks (H1) |
| **OCR mis-extraction corrupts pricing** | Medium | Golden-file harness + parser-version stamping + synthesized corpus (H2); confidence gates bulk-accept |
| **API/SW change breaks installed PWAs/TWAs offline** | Medium | SW cache-version bump + one-release grace period; never flip breaking client behavior in the client-shipping release |
| **CSS/UI silent regression** | Medium | Cypress visual-regression baseline (light/dark × mobile/desktop) in the same PR |
| **Rebrand churn** — image/repo/package rename breaks existing deploys | Medium | Dual-publish the old image tag for one release; GitHub repo redirects; DB names env-overridable; defer internal module rename (H0) |
| **Notification fatigue** from the proactive engine | Medium | Per-type opt-in, quiet hours, coalescing on the existing `dedup_key`; default conservative (H3) |
| **English fallback leaks raw keys** as de-default features land | Low | `i18n-tasks` CI parity guard (H1) |

> **Retired risk:** *Cross-tenant data leak* — eliminated by single-household-per-instance, not merely mitigated.

---

## 9. Definition of Done & success metrics

**Per-PR DoD (enforced in review):**
- Tests added/updated; relational-integrity coverage for any data-model change.
- i18n de/en parity (no missing keys; English fallback complete).
- Migration-rehearsal green against the prior-release seed **if the PR adds a migration**.
- Visual-regression baseline shipped in the same PR for any CSS/component change.
- Docs updated; RuboCop + (post-spike) Sorbet pass; coverage at/above floor.

**Milestone exit signals:**
- **H0:** every user-visible surface says Homestead; image/repo bridge clean; no data migration.
- **H1:** upgrade smoke test green on a blob-bearing seed; SSRF allowlist + rate-limiting live; both CI gates blocking with a coverage floor; OTel surfaces every job's health.
- **H1-UX:** native-feel bottom nav (incl. Todos/Calendar); no broken empty states; pills pass AA in dark mode.
- **H2:** real offer images; per-line confidence + safe confirm flow; Bring job-safe guard + tested conflict matrix; graceful feed degradation.
- **H3:** proactive reminders shipped behind a clean opt-in; live sync (if justified) channel-scoped + auth-tested; ≥1 "beyond food" pillar shipped; onboarding reduces drop-off.

**Product success metrics (emitted via OTel):**
- *Activation:* time-to-first-storage-item; % first-run sessions reaching ≥1 scanned/imported item; time-to-second-member; **push opt-in rate**.
- *Daily loop:* scans/week; receipts confirmed-vs-discarded; % grocery→storage conversion; offer-watchlist hit rate; **todos created/completed; comments per todo; calendar events per week**.
- *Proactive value:* reminders sent vs acted-on; expiries surfaced before lapse.
- *Reliability:* per-source feed health; recurring-job failure rate; **concurrent-edit rate** (gates live sync).
- *1.0 readiness:* upgrade smoke test green every release; CI gates blocking; the README "audit before prod" caveat retired against a defined "production-ready" checklist.

---

## 10. Open questions

1. **Rebrand depth confirmation.** User-facing + external rename now, internal
   Ruby module (`module Pantria`) deferred — confirm that split, or commit to the
   full internal rename in H0.
2. **First H3 pillar.** Beyond the proactive reminders engine, which "beyond
   food" pillar leads — **recurring chores**, **spend/budget analytics**, or the
   **document/warranty vault**? Metrics can decide, or product conviction can.
3. **Live sync demand.** Is real-time multi-member editing actually wanted, or
   does on-navigation rendering + the 5-min pulls already cover the household?
   (Determines whether `solid_cable` gets switched on for Turbo Streams.)
4. **IMAP TLS.** Make TLS mandatory (breaking plaintext-IMAP users) or keep
   `imap_ssl` configurable with a loud warning?
5. **Supported upgrade window.** N-1 → N only, or arbitrary version jumps?
   Determines whether migrations must stay replayable.
6. **"Production-ready" definition.** What checklist retires the README's "treat
   as a vendored library, audit before prod" caveat as an explicit 1.0 gate?

---
*Re-baselined for the Homestead era against the shipped codebase. Single-household
is the architectural keystone; tenant-isolation work is retired; the next bets
deepen one home rather than scale many.*
