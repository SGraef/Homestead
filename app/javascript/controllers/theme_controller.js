import { Controller } from "@hotwired/stimulus"

// Light/dark theme toggle.
//
// Persists the choice in localStorage so subsequent page loads pick it up
// before stylesheets render (see the inline boot script in the layout).
export default class extends Controller {
  static targets = ["button"]

  toggle() {
    const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark"
    document.documentElement.dataset.theme = next
    try { localStorage.setItem("pantria-theme", next) } catch (_) {}
  }
}
