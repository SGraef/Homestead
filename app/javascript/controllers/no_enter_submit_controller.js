import { Controller } from "@hotwired/stimulus"

// Attach to a <form> so a stray Enter in any text input doesn't submit it
// while the user is still editing other fields. Submit buttons keep
// working (you can still click them or tab to them and hit Enter), and
// textareas keep newlines.
//
// Used on the receipt-confirm form, which has many small inputs per row
// where Enter-to-submit would constantly fire the wrong action.
export default class extends Controller {
  guard(event) {
    if (event.key !== "Enter") return

    const t = event.target
    if (!t) return
    // Allow textareas: Enter is line-break, not submit, by browser default.
    if (t.tagName === "TEXTAREA") return
    // Allow submit buttons (input[type=submit] / button[type=submit]).
    if (t.matches?.("[type='submit']")) return

    event.preventDefault()
  }
}
