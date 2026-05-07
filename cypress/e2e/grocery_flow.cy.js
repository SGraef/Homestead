describe("Grocery list flow", () => {
  beforeEach(() => cy.login())

  it("adds a grocery item, marks it purchased, and shows it in storage", () => {
    cy.visit("/grocery_items/new")
    cy.get('select[name="grocery_item[product_id]"]').select(1)
    cy.get('input[name="grocery_item[quantity]"]').clear().type("1")
    cy.get('input[type="submit"]').click()

    cy.contains("Added to grocery list")
    cy.contains("button", "Mark purchased").first().click()

    cy.visit("/storage_items")
    cy.get("table tbody tr").should("have.length.at.least", 1)
  })
})
