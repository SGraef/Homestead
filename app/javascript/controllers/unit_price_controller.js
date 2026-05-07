import { Controller } from "@hotwired/stimulus"

// Live per-piece price calculator for receipt-confirm rows.
//
//   total / pieces = perPiece
//
// The integer-cent total comes from data-unit-price-total-value (set
// server-side from line.parsed_total_cents). The pieces value is read from
// the [data-unit-price-target="pieces"] input on every input event.
export default class extends Controller {
  static targets = ["pieces", "output"]
  static values  = { total: Number, currency: { type: String, default: "EUR" } }

  connect() { this.recompute() }

  recompute() {
    if (!this.hasPiecesTarget || !this.hasOutputTarget) return

    const piecesRaw = parseFloat((this.piecesTarget.value || "").replace(",", "."))
    const pieces    = Number.isFinite(piecesRaw) && piecesRaw > 0 ? piecesRaw : 1
    const perPiece  = (this.totalValue / pieces) / 100  // cents → major units

    this.outputTarget.textContent = this.format(perPiece)
  }

  format(value) {
    try {
      return new Intl.NumberFormat(document.documentElement.lang || "de", {
        style: "currency", currency: this.currencyValue
      }).format(value)
    } catch (_) {
      return value.toFixed(2)
    }
  }
}
