# Calendar

An in-app, server-rendered calendar for the household — no Node build, no
vendored calendar library. It shows manual events, projects todo due-dates, and
(optionally) two-way-syncs with Google Calendar.

## Views

Open `/calendar`. Three views are switched with `?view=` and navigated with
`?date=` Turbo Frame links:

- **Month** — a 7-column CSS-grid grid. Each cell carries a stable
  `data-cal-day="YYYY-MM-DD"` hook; events render as chips reusing the existing
  pill geometry (so they are dark-mode-correct for free). A day with more events
  than the chip cap shows a "+N weitere" overflow link; long titles ellipsis
  with the full text in `title=`.
- **Agenda** — a flat chronological list.
- **Day** — hour rows for a single day.

All times are stored in UTC and rendered in the household's timezone
(`Household.current.timezone`).

## Events

- **Create / edit** events from the calendar. The editor opens in a
  mobile-friendly modal (a native `<dialog>` driven by a Turbo Frame) so you
  stay on the calendar instead of switching pages.
- **Todo due-dates** project onto the grid **read-only** with a distinct accent
  and legend — they are driven by the existing todo table, so there is no
  duplication and no risk of an edit loop.

## Suggestions from comments

When a [todo comment](todos.md#comments) mentions a German date — e.g.
*"Termin am 5. Mai um 14 Uhr"* — Pantria runs a deterministic
`GermanDateExtractor` after the comment is saved and surfaces a standalone chip
beneath it: *"Termin erkannt … In Kalender übernehmen?"*.

- Nothing is ever created silently. A human click on the chip creates the
  `CalendarEvent` (`source: "comment_extraction"`), resolved in the household
  timezone and stored UTC.
- Negative or ambiguous phrases ("5 Äpfel", "Seite 14", a bare "14 Uhr" with no
  day) produce **no** chip — the parser favours precision over recall.
- Dismissing a chip persists the decision (`SuggestionDismissal`), so it never
  re-nags; editing the comment only re-offers genuinely changed dates.

The reverse direction also exists: a **manually-created** event whose text looks
task-like offers an "Aufgabe anlegen?" action that creates a linked todo. To
keep the loop closed, an event that was itself generated from a comment is never
re-scanned and never offers that action.

## Code references

- Models: [`app/models/calendar_event.rb`](https://github.com/SGraef/Pantria/blob/main/app/models/calendar_event.rb),
  [`app/models/suggestion_dismissal.rb`](https://github.com/SGraef/Pantria/blob/main/app/models/suggestion_dismissal.rb)
- Controllers: [`app/controllers/calendars_controller.rb`](https://github.com/SGraef/Pantria/blob/main/app/controllers/calendars_controller.rb),
  [`app/controllers/calendar_events_controller.rb`](https://github.com/SGraef/Pantria/blob/main/app/controllers/calendar_events_controller.rb)
- Date extraction: [`app/services/german_date_extractor.rb`](https://github.com/SGraef/Pantria/blob/main/app/services/german_date_extractor.rb)
