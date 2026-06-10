import { Controller } from "@hotwired/stimulus"

// Live per-piece price calculator for receipt-confirm rows.
//
//   total / pieces = perPiece
//
// The total comes from either the editable amount input
// ([data-unit-price-target="amount"], a major-units string like
// "1.99") OR -- as a fallback when the user hasn't touched it -- the
// server-rendered data-unit-price-total-value (integer cents, set
// from line.parsed_total_cents). Pieces is read from the
// [data-unit-price-target="pieces"] input on every input event.
export default class extends Controller {
  static targets = ["pieces", "amount", "output"]
  static values  = { total: Number, currency: { type: String, default: "EUR" } }

  connect() { this.recompute() }

  recompute() {
    if (!this.hasPiecesTarget || !this.hasOutputTarget) return

    const piecesRaw = parseFloat((this.piecesTarget.value || "").replace(",", "."))
    const pieces    = Number.isFinite(piecesRaw) && piecesRaw > 0 ? piecesRaw : 1

    // Editable amount wins; falls back to the OCR'd parsed total.
    let totalCents = this.totalValue
    if (this.hasAmountTarget) {
      const amountRaw = parseFloat((this.amountTarget.value || "").replace(",", "."))
      if (Number.isFinite(amountRaw) && amountRaw > 0) {
        totalCents = Math.round(amountRaw * 100)
      }
    }

    const perPiece = (totalCents / pieces) / 100   // cents → major units
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
