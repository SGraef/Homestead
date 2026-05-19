const { defineConfig } = require("cypress")

module.exports = defineConfig({
  // Dual reporters: the human-readable `spec` output stays in the CI
  // job log so failures are quick to scan, and `mocha-junit-reporter`
  // emits one XML per spec into `cypress/junit/` for GitLab to pick up
  // as `artifacts.reports.junit`. The `[hash]` placeholder ensures
  // one file per spec — without it the reporter overwrites a single
  // file and you lose all-but-the-last spec's results.
  reporter: "cypress-multi-reporters",
  reporterOptions: {
    reporterEnabled: "spec, mocha-junit-reporter",
    mochaJunitReporterReporterOptions: {
      mochaFile: "cypress/junit/results-[hash].xml",
      toConsole: false,
      testCaseSwitchClassnameAndName: true
    }
  },

  e2e: {
    baseUrl: process.env.CYPRESS_BASE_URL || "http://localhost:3000",
    specPattern: "cypress/e2e/**/*.cy.{js,ts}",
    supportFile: "cypress/support/e2e.js",
    video: false,
    screenshotOnRunFailure: true,
    setupNodeEvents(_on, _config) {}
  }
})
