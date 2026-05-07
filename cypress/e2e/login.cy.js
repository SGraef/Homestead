describe("Authentication", () => {
  it("rejects bad credentials", () => {
    cy.visit("/login")
    cy.get('input[name="email"]').type("demo@pantria.local")
    cy.get('input[name="password"]').type("wrong-password")
    cy.get('input[type="submit"]').click()
    cy.contains(/Invalid email or password/i)
  })

  it("logs in seeded demo user and lands on dashboard", () => {
    cy.login()
    cy.contains(/Dashboard/i)
  })
})
