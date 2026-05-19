describe("Barcode scan flow", () => {
  beforeEach(() => cy.login())

  it("opens the scan page and looks up a known barcode via manual entry", () => {
    cy.visit("/products/scan")
    cy.contains("Scan a barcode")

    // Demo seed creates a product with this barcode.
    cy.get('input[data-barcode-scanner-target="input"]').type("4006381333924")
    cy.contains("button", "Lookup").click()

    cy.get("#scan-result").contains(/Vollmilch/i)
  })

  it("offers to create a product for an unknown barcode", () => {
    cy.visit("/products/scan")
    cy.get('input[data-barcode-scanner-target="input"]').type("9999999999999")
    cy.contains("button", "Lookup").click()
    cy.get("#scan-result").contains(/Unknown barcode/i)
    cy.get("#scan-result").contains("Create a product for this code")
  })
})
