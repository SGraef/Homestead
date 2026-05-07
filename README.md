# Pantria

A household ERP focused on food storage, multi-store grocery price tracking
and barcode-driven inventory updates. German-first UI with English fallback,
REST API for mobile clients, and an OCR pipeline that turns supermarket
receipts into structured products, stores and prices.

## Features

- **Vorrat / Storage** — what's in the pantry, fridge, freezer or cellar; expiry warnings on the dashboard.
- **Tiefkühler / Freezer** — dedicated page (`/freezer`) for both bought-and-frozen items and homemade meals (g / portions / l). 3-month "stale in the freezer" warning on the dashboard, configurable via `FREEZER_STALE_DAYS`.
- **Einkaufsliste / Grocery list** — needed → purchased → automatic storage entry. Optional **two-way Bring! sync** (`/bring_connection`): Pantria → Bring on every write (push) plus a Bring → Pantria pull that runs every 5 minutes via Solid Queue's recurring scheduler (manual "Sync now" button on the connection page also available). Loops are prevented by a thread-local skip flag so pull-time writes don't bounce back to Bring!.
- **Barcode scan (frontend)** — native `BarcodeDetector` API where available (Chrome / Edge / Android), with a ZXing-js fallback (loaded via importmap from jsdelivr) for Safari iOS / Firefox / anything else. On a barcode miss the lookup falls back to Open Food Facts / Open Products Facts and prefills "Add product". **Mobile note:** browsers only grant camera access on `https://` URLs (or `localhost`); to scan from a phone on the LAN, run dev with the bundled self-signed-HTTPS override (see "Self-signed HTTPS for mobile scanning" below).
- **Receipt OCR** — upload a photo (JPEG/PNG/HEIC) or PDF; Tesseract + a heuristic parser extracts store, date, total and line items. PDFs are rasterized per-page via `pdftoppm` (poppler-utils). User confirms and rows become Stores + Products + Prices.
- **Multi-store prices** — every price is `(product, store, date)` in cents; cheapest known price surfaces on the product page.
- **REST API v1** — `/api/v1/{sessions, products, stores, prices, storage_items, grocery_items, receipts}` with bearer-token auth.
- **i18n** — German default, English fallback, locale switcher in the header.

## Stack

Rails 8 · MySQL 8.4 · Hotwire (Turbo + Stimulus + Importmap) · Sorcery
(auth) · Pundit (authz) · Active Storage · Sorbet + Tapioca · YARD · RSpec
+ FactoryBot · Cypress · Tesseract OCR.

## Quick start with Docker

Requires Docker Desktop (or any Compose v2-capable engine). MySQL, Redis,
Tesseract — everything runs in containers; no host dependencies needed.

```bash
# 1. Build images and start the dev stack (web on :3000, MySQL on :3306,
#    plus a Solid Queue `worker` container that drains background jobs and
#    runs the recurring Bring! pull).
docker compose up --build

# 2. In a second shell, prepare the database and seed the demo data.
docker compose exec web bin/rails db:prepare db:seed
```

The `worker` container loops on `bundle exec rake solid_queue:start`. It
restarts automatically (`restart: unless-stopped`) so it keeps retrying
until the Solid Queue tables exist after the first migration. Recurring
jobs live in [`config/recurring.yml`](config/recurring.yml).

Open <http://localhost:3000> and log in with the seeded demo user:

- **E-Mail**: `demo@pantria.local`
- **Passwort**: `password123`

Append `?locale=en` to any URL (or click the language switcher in the
header) to flip to English; the choice persists in your session.

### Other useful commands

```bash
# Tail the web logs
docker compose logs -f web

# Open a Rails console inside the running container
docker compose exec web bin/rails console

# Run a single migration / rollback
docker compose exec web bin/rails db:migrate
docker compose exec web bin/rails db:rollback

# Reset the database (drops + recreates + seeds)
docker compose exec web bin/rails db:drop db:create db:migrate db:seed

# Generate YARD docs into doc/yard/
docker compose exec web bundle exec yard

# Sorbet type-check
docker compose exec web bundle exec srb tc

# Stop everything
docker compose down

# Stop and wipe volumes (database + bundle cache)
docker compose down -v
```

### Self-signed HTTPS for mobile scanning

Mobile browsers refuse camera access (`getUserMedia`) on plain `http://` LAN
URLs — that's a browser policy, not a Rails toggle. To scan from a phone
on the same Wi-Fi during dev, use the bundled HTTPS override:

```bash
# Tell the cert which LAN IP your phone will type into the URL bar.
export LAN_IP=192.168.1.42

docker compose -f docker-compose.yml -f docker-compose.ssl.yml up --build
```

Then on the phone, open `https://192.168.1.42:3443/`. The browser will
warn about the self-signed cert — accept it once and the camera will work.

What the override does:

- Swaps the `web` container's command from `bin/dev` to `bin/dev-ssl`.
- Generates a self-signed cert into `tmp/ssl/` on first boot (covers
  `localhost`, the docker service name `web`, `127.0.0.1`, and `$LAN_IP`).
- Exposes Puma on `:3443` (HTTPS) alongside the existing `:3000` (HTTP).
- Allows private-IP hosts (`192.168.x.x`, `10.x.x.x`, `172.16-31.x.x`) in
  Rails' DNS-rebinding guard for development only.

Alternative: a TLS tunnel like `ngrok http 3000` or `cloudflared tunnel
--url http://localhost:3000` gives you a public `https://*.ngrok-free.app`
URL without any cert work.

## Running the test suite

A dedicated compose file spins up an isolated MySQL + the app + Cypress.

```bash
# RSpec + Sorbet, then Cypress against a freshly-seeded e2e instance
docker compose -f docker-compose.test.yml up --build --abort-on-container-exit

# Just RSpec (faster, while iterating)
docker compose run --rm web bundle exec rspec

# A single spec file
docker compose run --rm web bundle exec rspec spec/services/receipt_scanner/parser_spec.rb

# Cypress headless run only (assumes the app-e2e container is already up)
docker compose -f docker-compose.test.yml run --rm cypress
```

## Production-ready image

The root `Dockerfile` is multi-stage: `base → build → runtime`. The runtime
stage runs as a non-root user, ships only the slim runtime apt deps
(MySQL client, jemalloc, Tesseract, ImageMagick, tzdata), and exposes a
`/up` healthcheck.

```bash
# Build the prod image locally
docker build --target runtime -t pantria:local .

# Run it against an external MySQL
docker run --rm -p 3000:3000 \
  -e RAILS_ENV=production \
  -e RAILS_LOG_TO_STDOUT=1 \
  -e RAILS_SERVE_STATIC_FILES=1 \
  -e SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  -e DATABASE_HOST=db.example.com \
  -e DATABASE_USERNAME=pantria \
  -e DATABASE_PASSWORD=secret \
  -e DATABASE_NAME=pantria_production \
  -e APP_HOST=pantria.example.com \
  pantria:local
```

For production you run **two** containers from the same image:

```bash
# Web (Puma)
docker run -d --name pantria-web -p 3000:3000 \
  -e RAILS_ENV=production -e SECRET_KEY_BASE="…" -e DATABASE_HOST=… … \
  pantria:local

# Worker (Solid Queue) — same image, different command, db:prepare disabled
# so it doesn't race with the web container on first boot.
docker run -d --name pantria-worker \
  -e RAILS_ENV=production -e SECRET_KEY_BASE="…" -e DATABASE_HOST=… … \
  -e RAILS_RUN_DB_PREPARE=0 \
  pantria:local bundle exec rake solid_queue:start
```

The image is also produced and pushed automatically by the GitLab CI
pipeline (`.gitlab-ci.yml`) on every branch:

- `$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA`
- `$CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG`
- `$CI_REGISTRY_IMAGE:latest` — manual job on the default branch.

## REST API quickstart

```bash
# 1. Get a bearer token
curl -sX POST http://localhost:3000/api/v1/sessions \
  -d 'email=demo@pantria.local&password=password123'
# => { "token": "...", "user": { ... } }

TOKEN="paste-here"

# 2. Look up a barcode (local match → external → 404)
curl -s "http://localhost:3000/api/v1/products/lookup?barcode=4006381333924" \
  -H "Authorization: Bearer $TOKEN"

# 3. Upload a receipt for OCR (synchronous)
curl -s "http://localhost:3000/api/v1/receipts?inline=1" \
  -H "Authorization: Bearer $TOKEN" \
  -F image=@/path/to/receipt.jpg

# 4. Mark a needed grocery item as purchased by scanning its barcode
curl -sX POST http://localhost:3000/api/v1/grocery_items/scan_purchase \
  -H "Authorization: Bearer $TOKEN" \
  -d 'barcode=4006381333924'
```

## Project layout

```
app/
  controllers/         web + api/v1/* controllers
  models/              Household, Product, Store, Price, StorageItem,
                       GroceryItem, Receipt, ReceiptLineItem, ApiToken
  policies/            Pundit policies (household-scoped)
  services/
    barcode_lookup/    Open Food Facts + Open Products Facts adapters
    receipt_scanner/   Tesseract adapter + heuristic Parser
    receipt_confirmer.rb
  javascript/controllers/barcode_scanner_controller.js
  views/               Hotwire ERB templates (incl. Turbo Streams)
config/
  locales/{de,en}.yml  i18n
  routes.rb
db/migrate/            sorcery, households, products, stores, prices,
                       storage, grocery, receipts, active_storage
spec/                  RSpec model / policy / request / service / job specs
cypress/               E2E specs
```

## Configuration

Copy `.env.example` to `.env` for local overrides. Notable variables:

| Variable               | Default                  | Notes                          |
| ---------------------- | ------------------------ | ------------------------------ |
| `DATABASE_HOST`        | `db`                     | Compose service name           |
| `DATABASE_USERNAME`    | `pantria`                |                                |
| `DATABASE_PASSWORD`    | `pantria`                |                                |
| `DATABASE_NAME`        | `pantria_development`    |                                |
| `SECRET_KEY_BASE`      | (set in prod)            | `bin/rails secret`             |
| `OCR_LANG`             | `eng+deu`                | Tesseract language packs       |
| `OCR_PSM`              | `6`                      | Page-segmentation mode         |
| `OCR_PDF_DPI`          | `200`                    | DPI used to rasterize PDFs     |
| `FREEZER_STALE_DAYS`   | `90`                     | Stale-in-freezer warning threshold |
| `ALLOWED_API_ORIGINS`  | `*`                      | CORS allowlist for `/api/*`    |
| `MAIL_FROM`            | `no-reply@pantria.local` | `From:` header on outbound mail |
| `BRING_API_KEY`        | (built-in)               | Override Bring! client API key |
| `SMTP_ADDRESS`         | `localhost`              | Production SMTP host           |
| `SMTP_PORT`            | `587`                    | Production SMTP port           |
| `SMTP_USERNAME`        |                          | Optional auth                  |
| `SMTP_PASSWORD`        |                          | Optional auth                  |
| `SMTP_AUTH`            | `plain`                  | `plain` / `login` / `cram_md5` |
| `SMTP_STARTTLS`        | `true`                   |                                |

In **development** the mailer writes rendered emails to `tmp/mails/` —
read the activation link out of `tmp/mails/<email-address>` after sign-up.

## License

Internal project — no public license set.
