import { Controller } from "@hotwired/stimulus"

// Two flows wired into the product form:
//
//   1. fetchInfo()    — user has the barcode; we fill name/brand/etc. from
//                       /products/lookup.json (single match or nothing).
//   2. searchByName() — user has the name (and maybe brand); we list
//                       candidates from /products/search.json. Clicking
//                       "Use this" pastes a candidate (including its
//                       barcode) back into the form via useCandidate().
export default class extends Controller {
  static targets  = ["barcode", "name", "brand", "category", "unit",
                     "status", "results"]
  static values   = { url: String, searchUrl: String, token: String }
  static classes  = ["busy"]

  // -------- Lookup by barcode ----------------------------------------------

  async fetchInfo(event) {
    event?.preventDefault()
    const code = (this.barcodeTarget.value || "").trim()
    if (!code) {
      this.setStatus(this.t("empty"))
      return
    }
    this.setBusy(true)
    this.setStatus(this.t("looking_up"))

    try {
      const url  = `${this.urlValue}.json?barcode=${encodeURIComponent(code)}`
      const body = await this.getJson(url)

      if (body.source === "local") {
        this.setStatus(this.t("already_exists"))
        if (body.edit_url) window.location.assign(body.edit_url)
      } else if (body.source === "remote" && body.suggestion) {
        this.applySuggestion(body.suggestion)
        this.setStatus(this.tWith("found", body.suggestion.source || "external"))
      } else {
        this.setStatus(this.t("not_found"))
      }
    } catch (err) {
      this.setStatus(`${this.t("error")}: ${err.message}`)
    } finally {
      this.setBusy(false)
    }
  }

  // -------- Search by name (+ brand) ---------------------------------------

  async searchByName(event) {
    event?.preventDefault()
    const name  = this.hasNameTarget  ? this.nameTarget.value.trim()  : ""
    const brand = this.hasBrandTarget ? this.brandTarget.value.trim() : ""
    if (!name && !brand) {
      this.setStatus(this.t("searchEmpty"))
      return
    }
    this.setBusy(true)
    this.setStatus(this.t("searching"))
    this.clearCandidates()

    try {
      const params = new URLSearchParams()
      if (name)  params.set("name",  name)
      if (brand) params.set("brand", brand)
      const url  = `${this.searchUrlValue}.json?${params}`
      const body = await this.getJson(url)
      const list = Array.isArray(body.candidates) ? body.candidates : []

      if (list.length === 0) {
        this.setStatus(this.t("searchNoResults"))
      } else {
        this.renderCandidates(list)
        this.setStatus(this.tWith("searchFound", list.length))
      }
    } catch (err) {
      this.setStatus(`${this.t("error")}: ${err.message}`)
    } finally {
      this.setBusy(false)
    }
  }

  useCandidate(event) {
    event?.preventDefault()
    let payload
    try { payload = JSON.parse(event.currentTarget.dataset.payload || "{}") }
    catch (_) { return }

    if (this.hasBarcodeTarget && payload.barcode) this.barcodeTarget.value = payload.barcode
    this.applySuggestion(payload, { overwrite: true })
    this.clearCandidates()
    this.setStatus(this.t("applied"))
  }

  // -------- Helpers --------------------------------------------------------

  applySuggestion(s, { overwrite = false } = {}) {
    const set = (target, value) => {
      if (!target || !value) return
      if (overwrite || !target.value) target.value = value
    }
    if (this.hasNameTarget)     set(this.nameTarget,     s.name)
    if (this.hasBrandTarget)    set(this.brandTarget,    s.brand)
    if (this.hasCategoryTarget) set(this.categoryTarget, s.category)
    if (this.hasUnitTarget && s.unit) {
      const opt = Array.from(this.unitTarget.options).find(o => o.value === s.unit)
      if (opt) this.unitTarget.value = s.unit
    }
  }

  renderCandidates(list) {
    if (!this.hasResultsTarget) return
    this.resultsTarget.innerHTML = list.map((c, i) => `
      <div class="card card-flat" style="margin-bottom:var(--sp-2)">
        <p>
          <strong>${esc(c.name)}</strong>${c.brand ? ` — ${esc(c.brand)}` : ""}
          ${c.already_in_household
              ? `<span class="pill warn">${esc(this.t("alreadyInHousehold"))}</span>`
              : ""}
        </p>
        <p>
          <span class="pill">${esc(c.barcode || "")}</span>
          ${c.quantity_text ? `<span class="pill">${esc(c.quantity_text)}</span>` : ""}
          ${c.category ? `<span class="pill">${esc(c.category)}</span>` : ""}
        </p>
        ${c.image_url
            ? `<p><img src="${esc(c.image_url)}" alt="" style="max-height:80px;border-radius:.4rem"></p>`
            : ""}
        <button type="button"
                class="btn btn-sm"
                data-action="barcode-fetch#useCandidate"
                data-payload='${escAttr(JSON.stringify(c))}'>
          ${esc(this.t("useThis"))}
        </button>
      </div>
    `).join("")
  }

  clearCandidates() {
    if (this.hasResultsTarget) this.resultsTarget.innerHTML = ""
  }

  async getJson(url) {
    const resp = await fetch(url, {
      headers: { "Accept": "application/json", "X-CSRF-Token": this.tokenValue },
      credentials: "same-origin"
    })
    return resp.json().catch(() => ({}))
  }

  setBusy(busy) {
    if (!this.busyClasses.length) return
    busy
      ? this.element.classList.add(...this.busyClasses)
      : this.element.classList.remove(...this.busyClasses)
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text || ""
  }

  // Translated strings live on the controller element via data-* attrs so we
  // don't have to repeat them per locale in JS. Keys map to camelCase to
  // dataset properties: e.g. `t("looking_up")` → data-barcode-fetch-looking-up-text.
  t(key) {
    const camel = key.replace(/[-_]([a-z])/g, (_, c) => c.toUpperCase())
    return this.element.dataset[`barcodeFetch${camel.charAt(0).toUpperCase()}${camel.slice(1)}Text`] || ""
  }

  tWith(key, value) {
    return this.t(key).replace("%s", value)
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
