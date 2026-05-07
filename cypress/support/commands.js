// Sign in via the regular form. The seeded demo user lives in db/seeds.rb.
//
// Tests pass `?locale=en` once so subsequent assertions can stay in English
// regardless of the app's default locale (German). The locale persists in
// the session, so visits later in the same test don't need to repeat it.
Cypress.Commands.add("login", (email = "demo@pantria.local", password = "password123") => {
  cy.visit("/login?locale=en")
  cy.get('input[name="email"]').type(email)
  cy.get('input[name="password"]').type(password)
  cy.get('input[type="submit"]').click()
  cy.location("pathname").should("eq", "/")
})
