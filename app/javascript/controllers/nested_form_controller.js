import { Controller } from "@hotwired/stimulus"

// Generic add/remove for `accepts_nested_attributes_for` rows.
//
// Markup contract:
//   <div data-controller="nested-form">
//     <div data-nested-form-target="rows"> ... existing rows ... </div>
//     <template data-nested-form-target="template">
//       <!-- one row, with the index placeholder NEW_RECORD wherever Rails
//            renders the index in attribute names (e.g.
//            product[product_barcodes_attributes][NEW_RECORD][barcode]) -->
//     </template>
//     <button data-action="nested-form#add">+</button>
//   </div>
//
// Each row that may be deleted should call `data-action="nested-form#remove"`.
// For persisted rows the controller flips a `_destroy` hidden field instead
// of removing the DOM, so Rails knows to delete on save.
export default class extends Controller {
  static targets = ["rows", "template"]

  add(event) {
    event?.preventDefault()
    if (!this.hasTemplateTarget || !this.hasRowsTarget) return
    const html = this.templateTarget.innerHTML.replaceAll("NEW_RECORD", `new_${Date.now()}`)
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-nested-form-row]")
    if (!row) return

    const destroyField = row.querySelector("input[name$='[_destroy]']")
    if (destroyField) {
      destroyField.value = "1"
      row.style.display = "none"
    } else {
      row.remove()
    }
  }
}
