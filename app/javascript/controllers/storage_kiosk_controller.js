import { Controller } from "@hotwired/stimulus"

// Kiosk-style barcode scanner for bulk add-to-storage.
//
// Flow per detection:
//   1. Camera decoder (native `BarcodeDetector` or ZXing fallback) emits
//      a barcode string.
//   2. We POST it to `scanAddUrlValue` along with the currently-selected
//      location_id and the page's CSRF token.
//   3. The server returns a Turbo Stream that prepends a row to
//      #scan-log; we hand it to `Turbo.renderStreamMessage` so the DOM
//      updates without a navigation.
//   4. Debounce table is updated so the *same* barcode doesn't fire
//      again within DEBOUNCE_MS — without this, holding a package in
//      front of the camera adds the row 20+ times.
//
// The camera keeps running across detections. The user pauses
// explicitly (Stop button) when they're done.
const DEBOUNCE_MS = 2500

export default class extends Controller {
  static targets = ["video", "status", "manualInput", "location",
                    "startBtn", "stopBtn"]
  static values  = { scanAddUrl: String, token: String }

  connect() {
    this.scanning      = false
    this.stream        = null
    this.detector      = null
    this.zxingControls = null
    this.lastSeen      = new Map() // barcode -> Date.now() when last submitted
  }

  disconnect() {
    this.stop()
  }

  // ---- camera lifecycle ------------------------------------------

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
      this.swapButtons(true)
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
    this.setStatus(this.t("stopped"))
    this.swapButtons(false)
  }

  swapButtons(running) {
    if (this.hasStartBtnTarget) this.startBtnTarget.hidden = running
    if (this.hasStopBtnTarget)  this.stopBtnTarget.hidden  = !running
  }

  // ---- decoder paths --------------------------------------------

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
      if (codes.length > 0) this.handleDetection(codes[0].rawValue)
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
        this.handleDetection(result.getText())
      }
    )
  }

  // ---- detection + submit ---------------------------------------

  handleDetection(barcode) {
    const code = (barcode || "").trim()
    if (!code) return
    const now  = Date.now()
    const seen = this.lastSeen.get(code)
    if (seen && now - seen < DEBOUNCE_MS) return // ignore re-detection burst
    this.lastSeen.set(code, now)
    this.submit(code)
  }

  // Manual fallback form -- different transport, same submit path.
  submitManual(event) {
    event.preventDefault()
    if (!this.hasManualInputTarget) return
    const code = this.manualInputTarget.value.trim()
    if (!code) return
    this.submit(code)
    this.manualInputTarget.value = ""
  }

  async submit(barcode) {
    this.setStatus(this.t("detected", { value: barcode }))
    const body = new URLSearchParams()
    body.set("barcode",     barcode)
    body.set("location_id", this.hasLocationTarget ? this.locationTarget.value : "")

    const resp = await fetch(this.scanAddUrlValue, {
      method:      "POST",
      credentials: "same-origin",
      headers: {
        "Accept":         "text/vnd.turbo-stream.html",
        "X-CSRF-Token":   this.tokenValue,
        "Content-Type":   "application/x-www-form-urlencoded"
      },
      body: body.toString()
    })

    // Server returns turbo-stream on both success (200) and known
    // failure modes (422 unknown-barcode); render either.
    const stream = await resp.text()
    if (stream) window.Turbo.renderStreamMessage(stream)
  }

  // ---- error / status -------------------------------------------

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

  t(key, replacements = {}) {
    const raw = this.element.dataset[`i18n${key[0].toUpperCase()}${key.slice(1)}`]
    if (!raw) return key
    return Object.entries(replacements).reduce(
      (acc, [k, v]) => acc.replace(`%{${k}}`, v),
      raw
    )
  }
}
