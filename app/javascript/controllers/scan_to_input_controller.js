import { Controller } from "@hotwired/stimulus"

// Scan a barcode straight into a form input.
//
// Unlike `barcode_scanner_controller`, which POSTs the detected code
// to a lookup endpoint and renders a Turbo Stream, this one just
// fills the `input` target's value with the rawValue (and dispatches
// `input`/`change` events so any validation / autocomplete wired to
// the field picks it up). The user then completes the surrounding
// form (brand, variant text, …) and submits normally.
//
// Two decoder paths, same as the main scanner controller:
//   1. Native `BarcodeDetector` API where available (Chrome / Edge /
//      Android Chrome). Cheap, runs in a requestAnimationFrame loop.
//   2. ZXing-js fallback (`@zxing/browser`, vendored under
//      vendor/javascript/) for Safari iOS / Firefox / anything
//      missing BarcodeDetector.
export default class extends Controller {
  static targets = ["video", "input", "status", "panel", "toggle"]

  connect() {
    this.scanning      = false
    this.stream        = null
    this.detector      = null
    this.zxingControls = null
  }

  disconnect() {
    this.stop()
  }

  // Toggle the camera panel open/closed. Wired to a "Scan" button so
  // the camera doesn't initialise until the user actually wants it
  // (avoids prompting for camera permission on every page load).
  async toggle() {
    if (this.scanning) {
      this.stop()
      this.hidePanel()
    } else {
      this.showPanel()
      await this.start()
    }
  }

  async start() {
    if (this.scanning) return

    if (!navigator.mediaDevices?.getUserMedia) {
      this.setStatus(this.t("no_camera"))
      return
    }

    try {
      if ("BarcodeDetector" in window) {
        await this.startNative()
      } else {
        await this.startZXing()
      }
    } catch (err) {
      this.handleStartError(err)
    }
  }

  stop() {
    this.scanning = false
    if (this.stream) {
      this.stream.getTracks().forEach(t => t.stop())
      this.stream = null
    }
    if (this.zxingControls) {
      try { this.zxingControls.stop() } catch (_) {}
      this.zxingControls = null
    }
    if (this.hasVideoTarget) this.videoTarget.srcObject = null
  }

  // ---- decoder paths ----------------------------------------------

  async startNative() {
    this.stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: "environment" } }
    })
    this.videoTarget.srcObject = this.stream
    this.videoTarget.setAttribute("playsinline", "")
    await this.videoTarget.play()
    this.scanning = true

    this.detector ||= new window.BarcodeDetector({
      formats: ["ean_13", "ean_8", "upc_a", "upc_e", "code_128", "qr_code"]
    })
    this.setStatus(this.t("scanning"))
    this.tickNative()
  }

  async tickNative() {
    if (!this.scanning) return
    try {
      const codes = await this.detector.detect(this.videoTarget)
      if (codes.length > 0) {
        this.applyDetection(codes[0].rawValue)
        return
      }
    } catch (_) { /* per-frame errors aren't actionable */ }
    requestAnimationFrame(() => this.tickNative())
  }

  async startZXing() {
    this.setStatus(this.t("loading"))
    const { BrowserMultiFormatReader } = await import("@zxing/browser")
    const reader = new BrowserMultiFormatReader()
    this.videoTarget.setAttribute("playsinline", "")
    this.scanning = true
    this.setStatus(this.t("scanning"))

    this.zxingControls = await reader.decodeFromConstraints(
      { video: { facingMode: { ideal: "environment" } } },
      this.videoTarget,
      (result) => {
        if (!this.scanning || !result) return
        this.applyDetection(result.getText())
      }
    )
  }

  // ---- shared -----------------------------------------------------

  applyDetection(value) {
    this.stop()
    if (this.hasInputTarget) {
      this.inputTarget.value = value
      this.inputTarget.dispatchEvent(new Event("input",  { bubbles: true }))
      this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
      this.inputTarget.focus()
    }
    this.setStatus(this.t("detected", { value }))
    this.hidePanel()
  }

  showPanel() { if (this.hasPanelTarget) this.panelTarget.hidden = false }
  hidePanel() { if (this.hasPanelTarget) this.panelTarget.hidden = true  }

  handleStartError(err) {
    switch (err?.name) {
      case "NotAllowedError":      this.setStatus(this.t("denied"));    break
      case "NotFoundError":
      case "OverconstrainedError": this.setStatus(this.t("no_camera")); break
      case "NotReadableError":     this.setStatus(this.t("in_use"));    break
      default:                     this.setStatus(`Camera error: ${err?.message || err}`)
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  // Looks up a translated string from the controller's data-i18n-*
  // attributes (set by the view from I18n.t). Falls back to the key
  // itself so an unwired key is visible rather than silent.
  t(key, replacements = {}) {
    const raw = this.element.dataset[`i18n${key[0].toUpperCase()}${key.slice(1)}`]
    if (!raw) return key
    return Object.entries(replacements).reduce(
      (acc, [k, v]) => acc.replace(`%{${k}}`, v),
      raw
    )
  }
}
