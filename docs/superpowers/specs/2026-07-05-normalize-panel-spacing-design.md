# Normalize panel spacing to the Settings-pane rhythm

**Date:** 2026-07-05
**Scope:** `Sources/ClaudeLightApp/PanelContent.swift` only. View-layer spacing change; no logic, no core changes.

## Problem

The panel's two views breathe at different rhythms. The Settings pane uses a
uniform 12pt frame with 10pt internal spacing and reads as calm and airy. The
main session-list view is tighter — an 8pt frame, 4pt internal spacing, plus
ad-hoc `.padding(.top, 4)` on the header and `.padding(.bottom, 2)` on the
footer. The result: the Settings footer looks noticeably taller/airier than
the main view's header and footer, and the panel feels uneven when flipping
between the two.

The user prefers the Settings pane's airier feel and wants everything
normalized to it.

## Current spacing (baseline)

`SettingsPane` (the reference — unchanged by this work):
- `VStack(alignment: .leading, spacing: 10)` … `.padding(12)`

`PanelContent.sessionList`:
- outer `VStack(alignment: .leading, spacing: 4)` … `.padding(8)`
- header `HStack` … `.padding(.horizontal, 10).padding(.top, 4)`
- footer `HStack` … `.padding(.horizontal, 10).padding(.bottom, 2)`

## Change

Normalizing the two views to one rhythm turned out to need edits on both
sides — the vertical rhythm on the main view, and horizontal alignment plus a
few structural fixes on the Settings pane, discovered during live visual
review.

### `PanelContent.sessionList` (vertical rhythm)

1. Outer padding `8 → 12` — frame matches Settings.
2. Outer `VStack` `spacing: 4 → 10` — the header-divider and footer-divider
   gaps match Settings' airiness.
3. Header: drop `.padding(.top, 4)`; keep `.padding(.horizontal, 10)` only.
4. Footer: replace `.padding(.horizontal, 10).padding(.bottom, 2)` with
   `.padding(.leading, 8).padding(.trailing, 10)` — the `.bottom, 2` tuck is
   gone (the 12pt frame supplies it), and the leading is pulled in 2pt so the
   `gearshape` SF Symbol optically aligns with the header status dot (the
   symbol carries leading whitespace in its glyph box).
5. The two dividers stay full-width (no horizontal padding) — this is the
   "wide" divider both views share.

### `SettingsPane` (horizontal alignment + structure)

1. Frame padding `.padding(12)` → `.padding(.vertical, 12).padding(.horizontal, 22)`
   so the pane's content column matches the main view's, whose cards carry
   their own `.padding(.horizontal, 10)` on top of the 12pt frame (→ 22pt).
2. Add a `Divider()` beneath the Back/Settings header row so it is seated the
   same way the main-view header and the footer are (it previously ran
   straight into the toggles).
3. Both dividers get `.padding(.horizontal, -10)` so they extend past the 22pt
   content column out to the 12pt panel edge — matching the main view's wide
   dividers.
4. Wrap the three checkboxes in a `VStack(spacing: 10)` with
   `.padding(.vertical, 4)` so the toggle group breathes away from the
   dividers above and below it.

## Result

Both views share one system: 12pt vertical frame, 10pt stack spacing, a 22pt
content column (header dot, cards, toggles, footer all align), and full-width
"wide" dividers.

## Out of scope

- Scroll-clamped list height (`scrolledListHeight = 480`) stays exactly as-is.
  It is a max height, unrelated to the padding rhythm.
- The `.frame(width: 340)` panel width is unchanged.

## Testing & verification

- No logic change → the existing 279-test suite must pass unmodified
  (`swift test`). No new unit tests; this is pure view spacing with no
  view-snapshot harness in the repo.
- Manual verification (local build): flip between the session list and the
  Settings pane and confirm the header, footer, and both views now share one
  visual rhythm — no view reads as tighter or airier than the others. Check
  both the populated list and the empty ("No active sessions") state.
