import { Controller } from "@hotwired/stimulus"

// Subscribes the browser to Web Push after an explicit user gesture (never on
// load — a cold permission prompt can permanently deny the origin). Reads the
// VAPID public key from a <meta> tag and POSTs the PushSubscription JSON to the
// server. Localized status strings come in via data attributes so this stays
// i18n-agnostic. Degrades visibly (denied / unsupported) — silence is a bug.
export default class extends Controller {
  static targets = ["button", "status"]

  connect() {
    this.vapidKey = document.querySelector('meta[name="vapid-public-key"]')?.content
    this.refreshState()
  }

  async refreshState() {
    if (!this.supported()) { this.setStatus(this.data.get("unsupported")); this.hideButton(); return }
    if (Notification.permission === "denied") { this.setStatus(this.data.get("denied")); this.hideButton(); return }
    if (await this.existingSubscription()) { this.setStatus(this.data.get("enabled")); this.hideButton() }
  }

  supported() {
    return "serviceWorker" in navigator && "PushManager" in window &&
           "Notification" in window && Boolean(this.vapidKey)
  }

  async enable() {
    if (!this.supported()) return
    const permission = await Notification.requestPermission()
    if (permission !== "granted") { this.setStatus(this.data.get("denied")); return }

    try {
      const reg = await navigator.serviceWorker.ready
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this.urlBase64ToUint8Array(this.vapidKey)
      })
      await this.post(sub)
      this.setStatus(this.data.get("enabled"))
      this.hideButton()
    } catch (_) {
      this.setStatus(this.data.get("error"))
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
