import { Controller } from "@hotwired/stimulus"

// Barcode scanner Stimulus controller.
//
// Two decoder paths:
//   1. Native `BarcodeDetector` API — Chrome / Edge / Android, no JS overhead,
//      fastest. We drive a requestAnimationFrame loop against it.
//   2. ZXing-js (lazy-loaded from the CDN via the importmap) — used on
//      Safari iOS, Firefox, and any browser without `BarcodeDetector`.
//      ZXing manages the camera + decode loop itself; we just hand it the
//      <video> element and a callback.
//
// Either path resolves to the same flow: detected EAN → POST to the lookup
// URL → server replies with a Turbo Stream that updates `#scan-result`.
//
// Manual entry stays available even when the camera path fails (page not
// served via HTTPS, denied permission, no camera) so the user is never
// dead-ended.
export default class extends Controller {
  static targets = ["video", "input", "status"]
  static values  = { lookupUrl: String, token: String }

  connect() {
    this.scanning      = false
    this.stream        = null
    this.detector      = null
    this.zxingReader   = null
    this.zxingControls = null
  }

  disconnect() {
    this.stop()
  }

  async start() {
    if (this.scanning) return

    if (!navigator.mediaDevices?.getUserMedia) {
      this.setStatus(
        "Kamera nicht verfügbar — die Seite muss über HTTPS aufgerufen werden " +
        "(oder direkt vom Host-Rechner). Manuelle Eingabe unten verwenden."
      )
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

    // Native path: kill the MediaStream we own.
    if (this.stream) {
      this.stream.getTracks().forEach(t => t.stop())
      this.stream = null
    }
    // ZXing path: it owns the stream via `decodeFromConstraints`; the
    // returned controls release tracks for us.
    if (this.zxingControls) {
      try { this.zxingControls.stop() } catch (_) {}
      this.zxingControls = null
    }
    if (this.hasVideoTarget) this.videoTarget.srcObject = null
  }

  async manualLookup() {
    const value = (this.inputTarget.value || "").trim()
    if (!value) return
    await this.lookup(value)
  }

  // -------- decoder paths -------------------------------------------------

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
    this.setStatus("Camera running — point at a barcode…")
    this.tickNative()
  }

  async tickNative() {
    if (!this.scanning) return
    try {
      const codes = await this.detector.detect(this.videoTarget)
      if (codes.length > 0) {
        const value = codes[0].rawValue
        this.setStatus(`Detected ${value}, looking up…`)
        this.stop()
        await this.lookup(value)
        return
      }
    } catch (_) {
      // Per-frame errors aren't actionable; the loop retries.
    }
    requestAnimationFrame(() => this.tickNative())
  }

  async startZXing() {
    this.setStatus("Loading scanner…")
    const { BrowserMultiFormatReader } = await import("@zxing/browser")
    this.zxingReader = new BrowserMultiFormatReader()

    this.videoTarget.setAttribute("playsinline", "")
    this.scanning = true
    this.setStatus("Camera running — point at a barcode…")

    this.zxingControls = await this.zxingReader.decodeFromConstraints(
      { video: { facingMode: { ideal: "environment" } } },
      this.videoTarget,
      (result, _err, _controls) => {
        if (!this.scanning || !result) return
        const value = result.getText()
        this.scanning = false
        try { this.zxingControls?.stop() } catch (_) {}
        this.zxingControls = null
        this.setStatus(`Detected ${value}, looking up…`)
        this.lookup(value)
      }
    )
  }

  // -------- shared --------------------------------------------------------

  async lookup(barcode) {
    const url  = `${this.lookupUrlValue}?barcode=${encodeURIComponent(barcode)}`
    const resp = await fetch(url, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": this.tokenValue
      },
      credentials: "same-origin"
    })
    if (resp.ok) {
      const stream = await resp.text()
      window.Turbo.renderStreamMessage(stream)
      this.setStatus(`Looked up ${barcode}.`)
    } else {
      this.setStatus(`Lookup failed (${resp.status}).`)
    }
  }

  handleStartError(err) {
    const msg = err?.message || String(err)
    switch (err?.name) {
      case "NotAllowedError":
        this.setStatus("Kamera-Zugriff abgelehnt. Bitte in den Browser-Einstellungen erlauben.")
        break
      case "NotFoundError":
      case "OverconstrainedError":
        this.setStatus("Keine passende Kamera gefunden. Manuelle Eingabe unten verwenden.")
        break
      case "NotReadableError":
        this.setStatus("Kamera ist von einer anderen App belegt.")
        break
      default:
        this.setStatus(`Camera error: ${msg}`)
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
