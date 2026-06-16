# Pantria Roadmap — Beta → 1.0

> **Status:** Approved working plan (Delivery Lead synthesis of PO / Architect / Dev / QA / UX / UI planning round).
> **Horizon:** Next two quarters (Q1 = Foundation & Trust; Q2 = Core UX & Finish-the-Feature).
> **Theme:** *Earn trust before adding surface area.*

> **Update — single-household collapse.** Pantria is now single-household-per-instance
> (one deployment serves exactly one household; `Household.current`). This obsoletes the
> two largest tenant-isolation items below: the **M1 cross-tenant request-spec fuzz matrix**
> and the **M3 incremental `Current.household` model-scoping retrofit** are no longer needed —
> there is no cross-tenant boundary to defend. The "cross-tenant data leak" critical risk in §6
> is retired. Model-level relational integrity checks (Price↔store, RecipeIngredient↔product)
> still apply and stay.

---

## 1. Executive summary

Pantria is a feature-rich beta whose biggest gap is not features but **trust**: a self-hosted ERP holding a family's entire pantry, receipt, and price history must be safe to deploy, safe to upgrade, and provably isolated between households — and today none of those three is guaranteed (zero model-level `default_scope`, one policy spec, no tested upgrade path, plaintext Bring! OAuth tokens, decorative CI gates). Q1 therefore concentrates on a tight set of **non-negotiable trust foundations** — a cross-tenant test net, an upgrade/backup path proven against prod-shaped data, week-1 security wins, and real CI gates — while a **strictly schema-free, parallel UX track** (mobile bottom-nav, honest empty states, icon system) fixes the "feels like a website" regression that every self-hoster sees first. Q2 finishes the last 20% of already-advertised features (Marktguru offer images, OCR confidence + confirm-flow, integration hardening, invites) on top of the now-tested schema, and gates all genuinely-new work (live sync, AI meal-suggester) behind activation metrics. The unifying discipline: **nothing that widens the data model ships until the isolation net and the migration smoke test are green**, and **nothing that can corrupt pricing/grocery data ships without the signal that makes it safe** (per-line OCR confidence, defined Bring! conflict policy).

---

## 2. Guiding principles

1. **Tenant isolation is the load-bearing invariant.** A cross-household leak of receipts, prices, or grocery lists is existential. Every feature that touches the data model is gated on the isolation test net. *(Unanimous.)*
2. **Test net before refactor; behavioral baseline before behavioral change.** The additive cross-tenant request-spec matrix ships *first*; the `Current.household` model-scoping retrofit is layered incrementally behind it — never a big-bang `default_scope` on a 27-model LLM-coded base.
3. **No destructive upgrades, ever.** A green migration on an empty DB proves nothing. The upgrade path is only "done" when proven against a prior-release seed **with resolvable Active Storage blobs** and data-integrity assertions. No migration-bearing feature ships ahead of it.
4. **Gates must enforce, not observe.** RuboCop/Sorbet flip off `continue-on-error` via a ratchet; a coverage floor lands this half. Decorative gates on LLM-authored, security-sensitive code are unacceptable.
5. **Finish before you start.** The last 20% of advertised-but-under-delivered features (offer images, OCR trust, sync correctness, invites) outranks net-new modules. The AI meal-suggester and all new modules are frozen until core-loop activation metrics justify them.
6. **Schema-free UX runs in parallel, not behind.** Work touching zero models/migrations/tenancy (bottom-nav, empty states, contrast, icon sprite) ships alongside Q1 hardening — a hardened backend behind a nav that flex-wraps into three rows on a phone is still a failed first impression.
7. **Never ship the signal-less version of a data-corrupting action.** "Accept all auto-matched" waits on per-line OCR confidence; live broadcasts wait on a defined Bring! conflict policy and a job-safe echo guard.

---

## 3. Roadmap by milestone

Effort key: **S** ≤ ~2 days · **M** ≤ ~1 week · **L** ≤ ~2–3 weeks · **XL** multi-sprint.

### M0 — Week-1 Decisions & Quick Wins
**Goal:** Unblock the rest of the quarter with three product decisions and the cheapest high-value security/quality fixes.

| Initiative | Owner | Pri | Effort |
|---|---|---|---|
| **Deployment-posture decision** (LAN homelab vs internet-exposed) — gates SSRF/egress-proxy & IMAP-TLS scope | PO | P0 | S |
| **Bring! conflict-resolution policy** decision (last-write-wins / remote-wins / merge) — unblocks QA conflict tests & any live sync | PO | P0 | S |
| **Success-metrics definition + `ROADMAP.md`** (time-to-first-storage-item, scans/week, receipts confirmed-vs-discarded, members-per-household, concurrent-edit rate) | PO | P1 | S |
| **Encrypt `BringConnection.access_token`/`refresh_token`** + migration clearing plaintext rows (forces benign re-auth) | Architect/Dev | P0 | S |
| **ImageMagick/poppler `policy.xml`** size/decompression/content-type limits on the HEIC/PDF→Tesseract upload pipeline | Architect/Dev | P0 | S |
| **CI ratchet PR (part 1):** generate `.rubocop_todo.yml`, flip RuboCop to blocking-going-forward; add non-gating SimpleCov print+upload; run `srb tc` spike to capture exit status | Dev/QA | P0 | S |

**Exit criteria:** Posture & conflict-policy decisions recorded in `ROADMAP.md`; Bring! tokens encrypted in DB; upload pipeline has documented decompression/size limits; RuboCop blocking on new offenses; `srb tc` exit status + RuboCop offense count measured (sizes the Sorbet flip).

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

### M1 — Foundation & Trust (Q1 core)
**Goal:** Make Pantria provably isolated, safely upgradable, and operable on whatever surface the posture decision selects. *Nothing here is user-visible — that is the point.* Runs concurrently with the M1-UX track below.

| Initiative | Owner | Pri | Effort |
|---|---|---|---|
| **Cross-tenant request-spec fuzz matrix** — two households, asserting every API v1 + web index/show/update denies cross-tenant IDs; two-tiered (Pundit layer **and** model/DB layer); verifies background jobs (Bring pull, IMAP poll, offer sync) still resolve household explicitly. Co-owned. | QA + Dev/Architect | P0 | L |
| **Upgrade & data-migration path** — versioned GHCR releases, automated pre-upgrade DB + Active Storage backup, `rails pantria:upgrade` with rollback, **N-1 migration smoke test against a prior-release seed with resolvable Active Storage blobs**; assertions cover data integrity (households intact, attachments resolvable, no orphaned `ReceiptLineItems`/`Prices`). **One** shared fixture across delivery + QA harness. | Architect/Dev + QA | P0 | L |
| **Promote the 4 in-app FK-consistency checks** (`Price` store↔household, `RecipeIngredient`, `MealPlanEntry`, `StorageItem`) to **DB check constraints** | Architect | P1 | M |
| **CI ratchet PR (part 2):** flip Sorbet to blocking per spike result; ratchet `typed: strict` onto **security/money/parser files first** (`BringConnection`, `ImapPoller`, `Price`, receipt parser); land fixed `minimum_coverage` floor (baseline − ~2%) ~2 weeks after print step | Dev/QA | P1 | M |
| **SSRF host-allowlist across the 6 outbound fetchers** (marktguru/kaufda/mein_prospekt/flaschenpost/chefkoch/barcode_lookup) + block redirects to private IPs + **IMAP TLS verification policy** — *urgency posture-gated; in-process guard is posture-independent* | Architect/Dev | P1 | M |
| **API v1 correctness:** remove silent `default_household` fallback, require explicit household scoping — **with** SW cache-key version bump + one-release deprecation grace period; bearer-token rate-limiting only if posture = internet-exposed; wire OTel into the silent recurring jobs (Bring 5-min sync, IMAP poll, daily offers) with job-failure surfacing | Architect + Frontend | P1 | M |
| **i18n fallback parity guard** — `i18n-tasks` CI step failing on missing/unused keys (de.yml ~919 vs en.yml ~850) | QA | P2 | S |

**Exit criteria:** Isolation matrix green and **gating merges**; upgrade smoke test green against prod-shaped seed with blobs; RuboCop **and** Sorbet blocking with a coverage floor enforced; in-process SSRF allowlist + redirect-to-private-IP block live on all 6 fetchers; `default_household` fallback removed behind a deprecation grace period with SW cache-busting; English fallback parity enforced in CI.

---

### M1-UX — Mobile-First Foundation (parallel to M1)
**Goal:** Fix the biggest "feels like a website" regression. Touches zero models/migrations/tenancy, so it runs alongside M1 hardening.

| Initiative | Owner | Pri | Effort |
|---|---|---|---|
| **SVG icon sprite** (inline, `currentColor`-themeable) replacing emoji (🌓/🔍/📷) — *hard prerequisite for the bottom nav* | UI | P0 | M |
| **Bottom tab bar + overflow drawer** — single merged initiative. UX owns IA (primary 5 = Storage, Grocery, Scan, Offers, More); UI owns geometry, `safe-area-inset`, German worst-case label widths, Stimulus active-state wiring | UX (IA) + UI (exec) | P0 | L |
| **Branded empty/placeholder component primitives** — height-stable placeholder tile (reusing `illustration-basket.svg`), status badge (icon+text), empty-state block; **starts with offer cards** so they never render collapsed | UI | P0 | M |
| **Dark-mode pill/chip contrast fix** — `.pill.warn/success/danger` keep light-palette text while only `--*-soft` backgrounds are overridden → dark-on-dark, fails AA | UI | P1 | S |

**Exit criteria:** No emoji in primary nav/controls; installed PWA/TWA shows a native-feel bottom tab bar respecting notch safe-area; offer cards render a branded placeholder (never a collapsed block); status pills pass WCAG AA in dark mode. **Gate:** any CSS/component change ships its Cypress light+dark × mobile+desktop visual-regression baseline in the *same* PR.

---

### M2 — Finish the Features (Q2 core)
**Goal:** Close the last 20% of advertised-but-under-delivered features, now safely riding the tested schema and isolation net.

| Initiative | Owner | Pri | Effort |
|---|---|---|---|
| **Marktguru `image_url` derivation** (offers.rb:150 hardcoded `nil`) + designed placeholder contract agreed first; ships behind a golden fixture | Dev + UI | P1 | S |
| **Per-line OCR confidence scoring** (backend) — *no `confidence` field exists today; hard prerequisite for the bulk confirm action* | Dev | P1 | M |
| **Receipt-confirm UX:** mobile line-cards (reuse existing `.receipt-line__*` CSS), collapse-on-resolve, sticky confirmed-count — ships **first, no backend dep**; **"accept all auto-matched" held until confidence ships** | UX | P1 | L |
| **External-integration hardening:** VCR-style contract fixtures per feed/import, per-source health/staleness signal (generalize `ImapPoller` `last_polled_at`/`last_error`), retry/backoff + graceful degradation so one dead feed doesn't fail `sync_all_offers_job`; OTel-wired alerting | Dev | P1 | L |
| **Replace cross-process-unsafe Bring thread-local skip flag** (`grocery_item.rb:51-59` `Thread.current` doesn't survive Solid Queue workers) with explicit skip arg / DB-backed sync-origin column — *prerequisite for conflict tests and any live sync* | Dev/Architect | P1 | M |
| **Bring! conflict/dedup/race test matrix** — against the M0 product-defined policy | QA | P1 | M |
| **Receipt OCR golden-file harness** + parser-version stamping (idempotent re-parse); **synthesized** German-retailer corpus for breadth, real anonymized receipts as slow opt-in donation stream | QA | P1 | M |
| **Tokened household invite links + pending `Membership`** — auth boundary: SHA-256 digest at rest (mirror `ApiToken`), `SecureRandom.urlsafe_base64` ≥128 bits, expiry + single-use + household binding, **security sign-off before UI ships** | UX + Architect | P1 | M |
| **Honest empty/error/loading states** — live pending-receipt status (Turbo, not a refresh link), Bring!/IMAP health badge, low-confidence-line callout. UX owns which states + copy; UI owns components. | UX + UI | P1 | M |

**Exit criteria:** Offer cards show real images (placeholder on failure); receipts carry per-line confidence and a glanceable mobile confirm flow with bulk-accept *only* on matched/high-confidence lines; offer/recipe feeds degrade gracefully with per-source health visible; Bring! sync has a job-safe echo guard and a tested conflict matrix; a second household member can be invited via a secure link.

---

### M3 — Growth & Polish (metrics-gated)
**Goal:** Invest in collaboration and onboarding **only where metrics justify it.**

| Initiative | Owner | Pri | Effort |
|---|---|---|---|
| **Guided first-run onboarding checklist** (create household → scan/import first item → invite member) tied to activation metrics | PO + UX | P2 | M |
| **Live collaborative Turbo Stream sync** (grocery + storage) — **gated on:** (a) isolation suite + stream-authorization test, (b) defined Bring! conflict policy + job-safe skip guard, (c) OTel metrics confirming concurrent multi-member editing exists | UX + Dev | P2 | M |
| **Incremental `Current.household` + explicit-scoping concern**, model-by-model behind the fuzz matrix (Rails 8 `Current`, **not** a gem; **not** big-bang `default_scope`); adds DB-level FK guards | Architect/Dev | P2 | XL |
| **Versioned idempotent ingestion pipeline** (parser-version stamping consumed end-to-end, Offer `external_id`+`household_id`+`source` dedupe) | Architect | P2 | M |
| **Incremental utility layer + shared partials** — pulled by touched views only, behind visual-regression baseline | UI | P2 | M |
| **German-first density + responsive table audit** (wide tables → card pattern) | UI | P2 | M |
| **Barcode/scanner failure-path tests** (garbled barcode, all lookup sources miss/timeout, duplicate `ProductBarcode`) | QA | P2 | S |
| **PWA offline / TWA e2e** — sequenced after data-test selector pass + conflict-policy decision | QA | P2 | M |
| **Accessibility hardening pass** (non-color status, labeled/aria controls) — follows icon sprite | UX/UI | P2 | M |
| **Design-system docs page** in MkDocs | UI | P3 | S |
| **AI meal-suggester** — **FROZEN** until core-loop activation metrics justify it | PO | P3 | — |

**Exit criteria:** Live sync (if metrics justify) provably household-scoped with an authorization test; onboarding measurably reduces empty-pantry drop-off; model-level scoping landed incrementally without breaking background jobs; offline PWA tested against defined conflict behavior.

---

## 4. Cross-cutting workstreams

- **Quality / CI gates.** RuboCop blocking via `.rubocop_todo.yml` (M0) → Sorbet blocking per spike, `typed: strict` on security/money/parser files first (M1) → fixed `minimum_coverage` floor (M1, ~2 weeks after baseline print). **Cypress visual-regression** (light/dark × mobile/desktop) is a hard prerequisite shipping in the *same* PR as any CSS/component change. i18n parity guard in CI. *No `refuse_coverage_drop`* (flaky on parallel shards).
- **Security.** Week-1 unbundled wins (Bring token encryption, ImageMagick `policy.xml`). Posture-gated SSRF allowlist + IMAP-TLS — but the **in-process per-fetcher allowlist + private-IP redirect block is posture-independent and required**. Invite tokens treated as an auth boundary with security sign-off. App-wide encrypted-attributes-at-rest policy.
- **Observability.** Wire the just-added opt-in OTel into the silent recurring jobs (Bring 5-min sync, IMAP poll, daily offers) with job-failure surfacing and per-source health. Emit the M0-defined activation metrics to steer M3 sequencing.
- **Design system.** Icon sprite → bottom-nav → empty-state/badge primitives → incremental utility layer (pulled by touched views only) → docs page. Everything validated against worst-case **German** string lengths and dark-mode AA.
- **Data-migration / upgrade path.** **One** shared prior-release seed fixture with resolvable Active Storage blobs, co-owned by delivery + QA. Versioned GHCR tags, automated backup/rollback, integrity assertions. Hard gate on all migration-bearing features.

---

## 5. Sequencing & dependencies

```
M0 posture decision ──────────────► SSRF/IMAP-TLS scope (M1)
M0 Bring conflict policy ─────────► Bring conflict tests (M2) ──► live sync (M3)
M0 srb-tc spike ──────────────────► Sorbet blocking flip (M1)

Cross-tenant fuzz matrix (M1) ─┬─► incremental Current.household scoping (M3)
                               └─► live Turbo Stream broadcasts (M3)   [+ stream-auth test]

Upgrade smoke test green (M1) ────► ANY migration-bearing feature
                                     (OCR confidence column, invites, ...) (M2)

Icon sprite (M1-UX) ──────────────► bottom tab bar (M1-UX) ──► non-color a11y (M3)
Marktguru image_url + placeholder ─► offer cards never collapse
Per-line confidence (M2) ─────────► "accept all auto-matched" bulk action (M2)
Job-safe Bring skip guard (M2) ───► live sync (M3)
Visual-regression baseline ───────► any CSS/component refactor (same PR)
```

**Why these orderings:**
- **Test net before model surgery.** Big-bang `default_scope` on an LLM-coded base cascades through joins, eager-loads, serializers, and background jobs and leaks via associations/`.unscoped`. The additive request-spec matrix delivers most of the protection *now* and characterizes behavior so the XL scoping retrofit can be proven safe model-by-model.
- **Upgrade harness gates schema churn.** Invites add `Membership` state, OCR confidence adds columns — each adds a migration. Adding migrations before a tested upgrade path is exactly what bricks self-hoster data.
- **Live sync is a tenancy boundary, not a UI feature.** `turbo_stream_from` bypasses Pundit; a guessable per-household channel leaks live edits. It also fires from background Bring pull jobs where the thread-local skip flag fails — amplifying the duplicate-buy bug. Gated on isolation + job-safe guard + conflict policy + metrics.
- **Confidence gates bulk-accept.** "Accept all matched" without a confidence signal mass-confirms bad OCR into `Products`/`Prices`, corrupting the multi-store pricing differentiator.
- **Icon sprite gates the bottom nav.** Emoji can't inherit `currentColor` and render inconsistently — emoji in a native-feel bottom nav defeats its purpose.

### Conflict resolutions (Delivery Lead rulings)

- **PO's "30% of Q1 for a user-facing win" vs Architect's "P0 infra consumes Q1."** *Both red lines honored.* The M1-UX track (icon sprite, bottom-nav, empty states, contrast) runs **in parallel** with M1 hardening precisely because it touches zero models/migrations/tenancy. The Architect's gate ("isolation/upgrade must precede schema-widening features") binds only the schema-touching work, not schema-free UX. Result: Q1 ships visible adoption value *and* the trust foundations, without UX competing for the infra risk budget.
- **PO's "demote live sync, it's unmeasured" vs UX's original P0.** Demoted to **M3/P2**, triple-gated (isolation + conflict policy + metrics). UX conceded; Bring!'s 5-min pull may already cover the grocery case. The mobile bottom-nav stays the one protected user-facing P0.
- **Architect's `default_scope` L vs Dev/QA's "XL, test-net-first."** Resolved in Dev/QA's favor: matrix first (M1/L), scoping retrofit XL behind it (M3). The Architect conceded this explicitly.
- **Upgrade path M vs L.** Sized **L** — the prior-release seed with resolvable Active Storage blobs is the load-bearing deliverable; an empty-DB green proves nothing.
- **Sorbet "block now" vs "spike first."** Spike first (M0). RuboCop blocks immediately; Sorbet blocks conditionally and ratchets onto security/money/parser files first so the gate covers the highest-risk untyped code, not decorative coverage.
- **Two duplicate bottom-nav initiatives.** Merged: UX owns IA, UI owns visual/component execution + the prerequisite icon sprite. Duplicate empty-state work split the same way (UI = components, UX = which states + copy).
- **Marktguru fix buried in P2 pipeline.** Pulled out to a standalone **M2/P1/S** behind a fixture test; the heavy ingestion-pipeline versioning stays P2.

---

## 6. Key risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Cross-tenant data leak** — zero `default_scope`, 1 policy spec, `policy_scope` in 10/43 controllers | Critical | Additive fuzz matrix (M1) gating all data-model features; incremental `Current.household` + DB FK constraints (M3) behind the net |
| **Destructive upgrade** wipes pantry/receipt/price history — no tested path, 33 migrations | Critical | Versioned releases + automated backup/rollback + N-1 smoke test on prod-shaped seed **with blobs** (M1); hard gate on migration-bearing features |
| **Plaintext Bring OAuth tokens** — single DB dump compromises users' Bring accounts | High | Encrypt at rest + re-auth migration in week 1 (M0) |
| **SSRF / image-decoder RCE** via 6 outbound fetchers + HEIC/PDF→ImageMagick/poppler | High | `policy.xml` limits (M0); in-process host-allowlist + private-IP redirect block, posture-independent (M1) |
| **Silent quality rot** — `continue-on-error` RuboCop/Sorbet, no coverage floor, on LLM-authored code | High | Ratchet gates to blocking + coverage floor (M0–M1); `typed: strict` on highest-risk files first |
| **Bring! sync data loss/duplication** — process-local skip flag fails across Solid Queue workers; undefined conflict policy | High | Define conflict policy (M0); replace skip flag with job-safe mechanism + conflict test matrix (M2); block live sync until both land |
| **OCR mis-extraction corrupting pricing** — inline-string specs can't represent real variance | Medium | Golden-file harness + parser-version stamping + synthesized German corpus (M2); confidence gates bulk-accept |
| **API request-shape change breaks installed PWAs/TWAs offline** | Medium | SW cache-version bump + one-release deprecation grace period; never flip mandatory scoping in the client-shipping release (M1) |
| **CSS/UI silent regression** — RuboCop/Sorbet catch zero CSS | Medium | Cypress visual-regression baseline (light/dark × mobile/desktop) in the *same* PR as any refactor; incremental, view-pulled utility layer only |
| **Over-hardening LAN-only homelabs / under-protecting exposed hosts** | Medium | Week-1 posture decision gates egress-proxy & IMAP-TLS-mandatory scope |
| **English fallback leaks raw keys** as de-default features land | Low | `i18n-tasks` CI parity guard (M1) |

---

## 7. Definition of Done & success metrics

**Per-PR Definition of Done (enforced in review, uniform across authors):**
- Tests added/updated **+ cross-tenant isolation check** for any data-model change.
- **i18n de/en parity** (no missing keys; English fallback complete).
- **Migration-rehearsal green** against the prior-release seed *if the PR adds a migration*.
- **Visual-regression baseline** shipped in the same PR for any CSS/component change.
- Docs updated; RuboCop + (post-spike) Sorbet pass; coverage at or above floor.

**Milestone exit signals:**
- **M0:** posture + conflict-policy + metrics decisions recorded; Bring tokens encrypted; RuboCop blocking; `srb tc` status known.
- **M1:** isolation matrix gating merges; upgrade smoke test green on blob-bearing seed; both CI gates blocking with a coverage floor; SSRF allowlist live; `default_household` removed safely.
- **M1-UX:** native-feel bottom nav shipped; no broken offer cards; pills pass AA in dark mode.
- **M2:** real offer images; per-line confidence + safe confirm flow; graceful feed degradation with health surfacing; tested Bring conflict behavior; secure invite links.
- **M3:** metrics-justified live sync (household-scoped, auth-tested); onboarding reduces cold-start drop-off; model-level scoping landed without breaking jobs.

**Product success metrics (defined M0, emitted via OTel):**
- *Activation:* time-to-first-storage-item; % first-run sessions reaching ≥1 scanned/imported item; members-per-household; time-to-second-member.
- *Daily loop:* scans/week; receipts confirmed-vs-discarded; % grocery items converting to storage; offer-watchlist hit rate.
- *Reliability:* per-source feed health (success rate, staleness); recurring-job failure rate; concurrent-edit rate (gates live sync).
- *1.0 readiness:* zero known cross-tenant leaks; upgrade smoke test green every release; CI gates blocking; README "audit before prod" caveat retired against a defined "production-ready" checklist.

---

## 8. Open questions for stakeholders

1. **Primary target user for the next two quarters** — technical self-hosters (audit-tolerant, want robustness) or non-technical families (need turnkey onboarding, zero-fear upgrades)? Tilts emphasis between M1 hardening depth and M3 onboarding investment.
2. **Deployment posture** *(needed week 1)* — LAN homelab vs internet-exposed? Gates SSRF egress-proxy scope, IMAP-TLS-mandatory, and bearer-token rate-limiting.
3. **Bring! conflict-resolution contract** *(needed week 1)* — last-write-wins, remote-wins, or merge? Blocks the conflict test matrix and live sync; note the current echo-loop guard likely fails in production already.
4. **Definition of "1.0 / production-ready"** — does the README's "treat as a vendored library, audit before prod" caveat get retired as an explicit milestone, and against what checklist?
5. **IMAP TLS** — make TLS mandatory (breaking plaintext-IMAP users) or keep `imap_ssl` configurable with a loud warning?
6. **AI meal-suggester** — confirm it stays frozen until core-loop metrics justify it (Delivery Lead recommends yes).
7. **OCR fixture corpus** — sign-off on synthesizing German receipt layouts (Lidl/Aldi/Rewe/Edeka/dm) for breadth, with real anonymized receipts as an opt-in donation stream — confirming we will *not* block the harness on a real-receipt corpus.
8. **Supported upgrade window** — only N-1 → N sequential, or arbitrary version jumps? Determines whether migrations must stay replayable or can be collapsed per release.

---
*This document is the agreed working plan. Red lines from each role are encoded as the gates in §5 and the DoD in §7; deviations require Delivery Lead sign-off.*
