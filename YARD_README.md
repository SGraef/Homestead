# Pantria — Household ERP

A Rails 8 application for managing food storage, multi-store grocery prices,
and barcode-driven inventory updates. Authenticated with Sorcery, authorized
with Pundit, type-checked with Sorbet, documented with YARD.

## Domain

- **Household** — top-level tenant; everything else belongs to one.
- **Membership** — joins users to households with `admin` or `member` role.
- **Product** — catalog entry, optionally identified by barcode (EAN/UPC).
- **Store** — a place where products are bought; prices belong to it.
- **Price** — observed price per `(product, store, date)` in cents.
- **StorageItem** — a physical unit currently in pantry / fridge / freezer / cellar.
- **GroceryItem** — entry on the shopping list; on purchase becomes a StorageItem.

## Endpoints

The web frontend uses Hotwire (Turbo + Stimulus). The same data is also
exposed under `/api/v1/*` as JSON; see `Api::V1::*Controller`.

## Frontend barcode scan

`Stimulus::BarcodeScannerController` (in `app/javascript/controllers/`) uses
the browser's native `BarcodeDetector` API and falls back to manual entry.
After detection it hits `GET /products/lookup?barcode=…` which renders a
Turbo Stream into the page.
