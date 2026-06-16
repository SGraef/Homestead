import { Controller } from "@hotwired/stimulus"

// A native <dialog> whose body is a Turbo Frame ("modal"). When a link targets
// that frame (data-turbo-frame="modal"), the frame loads the content and this
// controller opens the dialog — no page navigation. Closes on Esc (native),
// backdrop click, or a [data-action="modal#close"] button; clears the frame on
// close so the same entry re-fetches next time.
export default class extends Controller {
  static targets = ["frame"]

  connect() {
    this.boundOpen = this.open.bind(this)
    this.frameTarget.addEventListener("turbo:frame-load", this.boundOpen)
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:frame-load", this.boundOpen)
  }

  open() {
    if (this.frameTarget.innerHTML.trim() !== "" && !this.element.open) {
      this.element.showModal()
    }
  }

  close() {
    this.element.close()
  }

  backdropClose(event) {
    if (event.target === this.element) this.element.close()
  }

  cleanup() {
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = ""
  }
}
