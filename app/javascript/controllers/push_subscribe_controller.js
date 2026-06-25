import { Controller } from "@hotwired/stimulus"

// Subscribes the browser to Web Push after an explicit user gesture (never on
// load — a cold permission prompt can permanently deny the origin). Reads the
// VAPID public key from a <meta> tag and POSTs the PushSubscription JSON to the
// server. Localized status strings come in via data attributes so this stays
// i18n-agnostic. Degrades visibly with a *specific* reason (insecure context,
// server not configured, browser unsupported, denied) — silence is a bug.
export default class extends Controller {
  static targets = ["button", "status"]

  connect() {
    this.vapidKey = document.querySelector('meta[name="vapid-public-key"]')?.content
    this.refreshState()
  }

  async refreshState() {
    // Order matters: report the most specific, actionable blocker first.
    if (!this.browserSupported()) { return this.block("unsupported") }
    if (!window.isSecureContext)  { return this.block("insecure") }       // http:// over a LAN IP, etc.
    if (!this.vapidKey)           { return this.block("not-configured") }  // server has no VAPID keys
    if (Notification.permission === "denied") { return this.block("denied") }
    if (await this.existingSubscription()) { this.setStatus(this.data.get("enabled")); this.hideButton() }
    // else: leave the button visible so the user can enable.
  }

  // Just the browser API surface — not the environment (secure context / keys).
  browserSupported() {
    return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
  }

  async enable() {
    if (!this.browserSupported() || !window.isSecureContext || !this.vapidKey) return
    const permission = await Notification.requestPermission()
    if (permission !== "granted") { this.setStatus(this.data.get("denied")); return }

    try {
      const reg = await navigator.serviceWorker.ready
      const sub = await this.subscribe(reg)
      await this.post(sub)
      this.setStatus(this.data.get("enabled"))
      this.hideButton()
    } catch (err) {
      // Surface the real reason instead of swallowing it (Android Chrome is the
      // strictest about this) so the failure is debuggable.
      console.warn("[push] subscribe failed:", err)
      this.setStatus(`${this.data.get("error")} (${err?.name || err})`)
    }
  }

  async subscribe(reg) {
    const key = this.urlBase64ToUint8Array(this.vapidKey)
    try {
      return await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key })
    } catch (err) {
      // A subscription created with a *different* VAPID key (e.g. the server
      // rotated/regenerated keys) makes Android throw InvalidStateError. Drop
      // the stale one and retry once.
      if (err?.name !== "InvalidStateError") throw err
      const stale = await reg.pushManager.getSubscription()
      if (stale) await stale.unsubscribe()
      return await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key })
    }
  }

  async existingSubscription() {
    try {
      const reg = await navigator.serviceWorker.ready
      return await reg.pushManager.getSubscription()
    } catch (_) {
      return null
    }
  }

  async post(sub) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    await fetch(this.data.get("create-url"), {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token || "" },
      body: JSON.stringify(sub.toJSON())
    })
  }

  block(reasonKey) { this.setStatus(this.data.get(reasonKey)); this.hideButton() }
  setStatus(msg) { if (this.hasStatusTarget && msg) this.statusTarget.textContent = msg }
  hideButton() { if (this.hasButtonTarget) this.buttonTarget.hidden = true }

  urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    const raw = atob(base64)
    const out = new Uint8Array(raw.length)
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
    return out
  }
}
