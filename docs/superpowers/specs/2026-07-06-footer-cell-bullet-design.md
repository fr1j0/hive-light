# Footer Cell Bullet — Design

**Date:** 2026-07-06
**Status:** Approved (mockup variant A, footer only)

## What

A hollow hive-cell glyph before the "Hive Light v\<version\>" wordmark in the
dropdown panel's footer — the panel's single brand touch. Everything else in
the panel is unchanged.

## Why

The hive metaphor (README dictionary definition: "projects as cells") so far
lives only outside the app. The footer wordmark row is the one place inside
the panel where a brand glyph is chrome, not signal: it appears exactly once,
carries no state, and can borrow the text's own color without adding a new
color role — consistent with the panel's visual grammar (colors reserved by
role, chrome pays rent).

## Decisions (from mockup review)

- **Shape:** SF Symbol `hexagon` — hollow, pointy-top. No custom `Shape`.
- **Size:** 9 pt symbol next to the existing 11 pt footer text.
- **Color:** `.tertiary`, identical to the version text — the glyph reads as
  part of the wordmark, not as a new signal.
- **Spacing:** 5 pt between glyph and text.
- **Scope:** footer only. Explicitly rejected in the same mockup pass:
  - status dots as hexagons (at 9 px the corners vanish; branding does not
    belong on a status signal, and one-per-row would overuse the motif);
  - any other panel placement (card titles, grouped block headers).
- **Motif budget:** one cell touch per surface — README has the dictionary
  definition, the app icon has its own mark, the panel gets this bullet.

## Implementation shape

`PanelContent.swift` footer (currently `Text("Hive Light v\(version)")`,
11 pt, `.tertiary`): wrap in an `HStack(spacing: 5)` of
`Image(systemName: "hexagon")` at 9 pt plus the existing text, with the
existing `.tertiary` style applied to the pair. Use a default
(center-aligned) `HStack` — **revised after live check:** the spec first
prescribed `.firstTextBaseline`, but the SF Symbol's ascent grows the pair's
frame upward under baseline alignment, seating the whole lockup visibly low
in the footer row. Center alignment seats both the glyph on the text and the
pair in the row. The glyph is decorative:
hidden from accessibility (the row already reads "Hive Light v\<version\>").

## Testing

No logic changes — this is pure view chrome, out of reach of the XCTest
suite by design. Verification is the existing live-check: build, swap into
/Applications (re-sign flow), open the panel, confirm the glyph in both
light and dark appearance and that the footer's leading/trailing optical
alignment is undisturbed. Existing tests must stay green (no regressions
from the edit).

## Out of scope

- Menu-bar icon shape (stays the traffic-light lamp).
- README state-table chips (separately decided: stay faithful rounded rects).
- Empty-state or Settings-pane cell accents (would exceed the motif budget).
