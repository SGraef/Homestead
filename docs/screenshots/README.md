# Screenshots

This directory holds the screenshots referenced from the docs pages
under `docs/features/` and friends.

## Two-stage workflow

1. **Placeholders** — every page references an `.svg` here. The SVGs
   are wireframe-style mockups (window chrome + sidebar + content
   blocks) so the docs render cleanly even before real screenshots
   exist. Regenerate them anytime by re-running:

   ```bash
   ./scripts/generate-screenshot-placeholders.sh
   ```

   The template lives in that script; tweak the layout there if you
   want a different placeholder style.

2. **Real screenshots** — once the app has interesting seed data, run
   the Cypress capture spec:

   ```bash
   docker compose -f docker-compose.test.yml run --rm cypress \
     bunx cypress run --spec cypress/e2e/screenshots.cy.js \
                      --config screenshotsFolder=/e2e/cypress/screenshots
   ```

   The spec walks every key view and writes `<filename>.png` files
   into Cypress's `screenshots/` directory. Copy the PNGs over the
   matching SVGs here (same basename, different extension — update the
   `.md` references at the same time, or just delete the SVG so the
   PNG wins via the filename match).

## File map

| Filename                       | Page                                              |
| ------------------------------ | ------------------------------------------------- |
| `storage-index.svg`            | `features/storage.md`                             |
| `freezer.svg`                  | `features/storage.md`                             |
| `storage-scan-add.svg`         | `features/storage.md`                             |
| `storage-used.svg`             | `features/storage.md`                             |
| `grocery-list.svg`             | `features/grocery-list.md`                        |
| `grocery-offer-match.svg`      | `features/grocery-list.md`                        |
| `barcode-scan.svg`             | `features/barcode-scanning.md`                    |
| `receipt-upload.svg`           | `features/receipts.md`                            |
| `receipt-confirm.svg`          | `features/receipts.md`                            |
| `recipe-show.svg`              | `features/recipes.md`                             |
| `recipe-used.svg`              | `features/recipes.md`                             |
| `meal-plan.svg`                | `features/recipes.md`                             |
| `offers.svg`                   | `features/offers.md`                              |
| `offers-manual.svg`            | `features/offers.md`                              |
| `inbound-email.svg`            | `features/inbound-email.md`                       |
| `pwa-install.svg`              | `pwa-android.md`                                  |

When you add a new doc page that needs a screenshot, list it here too
and add an entry to `scripts/generate-screenshot-placeholders.sh` so
the placeholder gets generated.

## Updating after the fact

The doc markdown references images by exact filename. To swap a
placeholder for a real PNG:

1. Capture the PNG (manually or via the Cypress spec).
2. Place it next to the SVG with the same basename.
3. Change the markdown reference from `.svg` to `.png` — or just
   delete the SVG once you're sure you don't need both.

The Cypress spec writes PNGs by default. If you keep both side-by-side
you'll want to be intentional about which gets referenced — there's no
auto-pick.
