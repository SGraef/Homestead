# frozen_string_literal: true
# typed: ignore

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true

# Browser barcode decoder used as a fallback when the native BarcodeDetector
# API is unavailable (Safari iOS, Firefox, …). Vendored under
# vendor/javascript/ so the PWA can serve it from the same origin --
# letting the service worker cache it for offline use and avoiding a
# cross-origin CDN hop on every cold load. Updating: re-fetch all three
# from jsdelivr and re-apply the import-path rewrites in vendor/javascript/.
pin "@zxing/browser",  to: "@zxing--browser.js"
pin "@zxing/library",  to: "@zxing--library.js"
pin "ts-custom-error", to: "ts-custom-error.js"

pin_all_from "app/javascript/controllers", under: "controllers"
