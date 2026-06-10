// Screenshot capture spec for the docs site.
//
// Not part of the regular test suite (CI doesn't run this on every
// push). Trigger it manually after the seed data is loaded:
//
//   docker compose -f docker-compose.test.yml run --rm cypress \
//     bunx cypress run --spec cypress/e2e/screenshots.cy.js
//
// The captured PNGs land in cypress/screenshots/screenshots.cy.js/.
// Copy them over to docs/screenshots/ (matching basenames) and the
// docs site picks them up on next mkdocs build.
//
// Expects a logged-in seeded household with at least:
//   - 3+ Products
//   - 1+ StorageItem
//   - 1+ GroceryItem
//   - 1+ Receipt (status: parsed or confirmed)
//   - 1+ Recipe
// Seed via spec/factories or bin/rails db:seed before running.

const cap = (path, name, after = () => {}) => {
  cy.visit(path)
  cy.wait(400) // let images / charts settle
  after()
  cy.screenshot(name, { capture: "viewport", overwrite: true })
}

describe("Documentation screenshots", () => {
  beforeEach(() => {
    cy.login() // command defined in cypress/support/commands.js
    cy.viewport(1280, 800)
  })

  it("captures storage views", () => {
    cap("/storage_items", "storage-index")
    cap("/freezer", "freezer")
    cap("/storage_items/scan", "storage-scan-add")
    // For "used N" we open the storage page and scroll to a row.
    cap("/storage_items", "storage-used", () => {
      cy.get('form[action*="decrement"]').first().scrollIntoView()
    })
  })

  it("captures grocery views", () => {
    cap("/grocery_items", "grocery-list")
    // Offer-chip variant only renders when the seed actually has a
    // matched current offer for one of the grocery rows. Capture the
    // chip-scrolled screenshot when present; otherwise reuse the
    // plain list view -- better than failing the run for missing
    // seed data.
    cy.visit("/grocery_items")
    cy.wait(400)
    cy.get("body").then(($body) => {
      if ($body.find(".chip.success").length) {
        cy.get(".chip.success").first().scrollIntoView()
      }
      cy.screenshot("grocery-offer-match", { capture: "viewport", overwrite: true })
    })
  })

  it("captures the barcode scanner page", () => {
    cap("/products/scan", "barcode-scan")
  })

  it("captures receipt OCR views", () => {
    cap("/receipts/new", "receipt-upload")
    // Expects at least one parsed receipt to exist.
    cy.visit("/receipts")
    cy.get('table a[href*="/receipts/"]').first().click()
    cy.wait(400)
    cy.screenshot("receipt-confirm", { capture: "viewport", overwrite: true })
  })

  it("captures recipes + meal plan", () => {
    cy.visit("/recipes")
    cy.get('a[href*="/recipes/"]').first().click()
    cy.wait(400)
    cy.screenshot("recipe-show", { capture: "viewport", overwrite: true })
    cy.screenshot("recipe-used", {
      capture: "viewport",
      overwrite: true,
      clip:     { x: 0, y: 200, width: 1280, height: 320 }
    })
    cap("/meal_plan", "meal-plan")
  })

  it("captures the offers page", () => {
    cap("/offers", "offers")
    // Routed under `path: "offers/manual"` (see config/routes.rb).
    cap("/offers/manual/new", "offers-manual")
  })

  it("captures the inbound email config", () => {
    cap("/households/inbound_emails", "inbound-email")
  })

  it("captures the PWA install hint", () => {
    // Cypress refuses to `cy.visit()` non-HTML responses (the manifest
    // is application/manifest+json), and the OS-native "Add to Home
    // Screen" prompt isn't reachable from inside the browser anyway.
    // Use the logged-in dashboard as a stand-in showing what the
    // installed PWA opens to; the docs editor crops/annotates after.
    cap("/", "pwa-install")
  })
})
