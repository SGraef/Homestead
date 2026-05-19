// Smoke test for the receipt upload flow. We don't run real OCR in CI; a tiny
// fake image is enough to exercise the upload + show-page rendering. The
// background job processes asynchronously, so we just assert the upload itself.
describe("Receipt upload", () => {
  beforeEach(() => cy.login())

  it("uploads a receipt image and lands on the receipt page", () => {
    cy.visit("/receipts/new")

    // Inline 1x1 PNG -- tiny enough to keep the test self-contained and
    // independent of OCR infrastructure (the controller only needs *any*
    // attachable file to enqueue ProcessReceiptJob).
    const png1x1 =
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8//8/AwAI/AL+RGSMHAAAAABJRU5ErkJggg=="
    cy.get('input[type="file"]').selectFile({
      contents: Cypress.Buffer.from(png1x1, "base64"),
      fileName: "tiny.png",
      mimeType: "image/png"
    })

    cy.get('input[type="submit"]').click()
    cy.contains(/Receipt uploaded/i)
    // Show page header is "<%= t('receipt.title') %> #<id>" -- "Receipts #<n>"
    // in English. Match the trailing "#<digits>" rather than the
    // singular/plural-sensitive prefix.
    cy.contains(/#\d+/)
  })
})
