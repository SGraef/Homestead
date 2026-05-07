import { Controller } from "@hotwired/stimulus"

// Per-receipt-line product search. Reuses the same `/products/search.json`
// endpoint the product form uses (Open Food Facts CGI search via
// BarcodeLookup.search), but scoped to a single line: the user clicks 🔍,
// gets up to 5 candidates with barcodes / brands / sizes, and picks one to
// fill the line's name input. Optionally also fills the line's unit
// dropdown (when the OFF result has a parseable unit).
export default class extends Controller {
  static targets  = ["nameInput", "unitSelect", "results"]
  static values   = { url: String, token: String }

  async search(event) {
    event?.preventDefault()
    const name = (this.hasNameInputTarget ? this.nameInputTarget.value : "").trim()
    if (!name) {
      this.render(`<p class="caption">${this.t("empty")}</p>`)
      return
    }

    this.render(`<p class="caption">${this.t("searching")}</p>`)

    try {
      const params = new URLSearchParams({ name })
      const resp   = await fetch(`${this.urlValue}.json?${params}`, {
        headers: { "Accept": "application/json", "X-CSRF-Token": this.tokenValue },
        credentials: "same-origin"
      })
      const body = await resp.json().catch(() => ({}))
      const list = Array.isArray(body.candidates) ? body.candidates : []

      if (list.length === 0) {
        this.render(`<p class="caption">${this.t("not_found")}</p>`)
        return
      }

      this.render(list.map((c, i) => this.renderCandidate(c, i)).join(""))
    } catch (err) {
      this.render(`<p class="caption">${this.t("error")}: ${esc(err.message)}</p>`)
    }
  }

  apply(event) {
    event?.preventDefault()
    let payload
    try { payload = JSON.parse(event.currentTarget.dataset.payload || "{}") }
    catch (_) { return }

    if (this.hasNameInputTarget && payload.name) this.nameInputTarget.value = payload.name
    if (this.hasUnitSelectTarget && payload.unit) {
      const opt = Array.from(this.unitSelectTarget.options).find(o => o.value === payload.unit)
      if (opt) this.unitSelectTarget.value = payload.unit
    }
    this.render("")
  }

  // ---- internals ---------------------------------------------------------

  renderCandidate(c, i) {
    const used = c.already_in_household
      ? `<span class="pill warn">${esc(this.t("already_in_household"))}</span>`
      : ""
    return `
      <div class="card card-flat" style="margin:var(--sp-1) 0;padding:var(--sp-2)">
        <div style="display:flex;gap:var(--sp-1);align-items:center;flex-wrap:wrap">
          <strong>${esc(c.name || "")}</strong>
          ${c.brand ? `<span>— ${esc(c.brand)}</span>` : ""}
          ${used}
        </div>
        <div style="display:flex;gap:var(--sp-1);align-items:center;flex-wrap:wrap;margin-top:var(--sp-1)">
          ${c.barcode ? `<span class="pill">${esc(c.barcode)}</span>` : ""}
          ${c.quantity_text ? `<span class="pill">${esc(c.quantity_text)}</span>` : ""}
          ${c.category ? `<span class="pill">${esc(c.category)}</span>` : ""}
          <button type="button" class="btn btn-sm"
                  data-action="receipt-search#apply"
                  data-payload='${escAttr(JSON.stringify(c))}'>
            ${esc(this.t("use_this"))}
          </button>
        </div>
      </div>
    `
  }

  render(html) {
    if (this.hasResultsTarget) this.resultsTarget.innerHTML = html
  }

  // Translated strings come in as data-* attrs on the controlled element
  // (so we don't have to repeat translations in JS).
  t(key) {
    const camel = key.replace(/[-_]([a-z])/g, (_, c) => c.toUpperCase())
    return this.element.dataset[`receiptSearch${camel.charAt(0).toUpperCase()}${camel.slice(1)}Text`] || ""
  }
}

function esc(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;")
}
function escAttr(s) {
  return esc(s).replace(/`/g, "&#96;")
}
