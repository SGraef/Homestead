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
    cap("/grocery_items", "grocery-offer-match", () => {
      cy.get(".chip.success").first().scrollIntoView()
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
    cap("/manual_offers/new", "offers-manual")
  })

  it("captures the inbound email config", () => {
    cap("/households/inbound_emails", "inbound-email")
  })

  it("captures the PWA install hint", () => {
    // No native install prompt to capture; use the manifest page as a
    // proxy and let the docs editor crop / annotate after the fact.
    cap("/manifest.json", "pwa-install")
  })
})
