# frozen_string_literal: true
# typed: ignore

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true

# Browser barcode decoder used as a fallback when the native BarcodeDetector
# API is unavailable (Safari iOS, Firefox, …). `+esm` makes jsdelivr ship a
# single self-contained ESM bundle so we don't have to pin the transitive
# `@zxing/library` dep separately.
pin "@zxing/browser",
    to: "https://cdn.jsdelivr.net/npm/@zxing/browser@0.1.5/+esm"

pin_all_from "app/javascript/controllers", under: "controllers"
