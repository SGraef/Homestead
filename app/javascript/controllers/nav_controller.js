import { Controller } from "@hotwired/stimulus"

// Mobile navigation: opens/closes the "More" sheet from the bottom tab bar.
// The sheet markup re-renders on every Turbo navigation, so it naturally
// resets to closed when the user taps through to a page — no manual cleanup
// needed beyond restoring body scroll.
export default class extends Controller {
  static targets = ["sheet"]

  openSheet() {
    this.sheetTarget.classList.add("is-open")
    document.body.classList.add("nav-sheet-open")
  }

  closeSheet() {
    this.sheetTarget.classList.remove("is-open")
    document.body.classList.remove("nav-sheet-open")
  }

  disconnect() {
    document.body.classList.remove("nav-sheet-open")
  }
}
