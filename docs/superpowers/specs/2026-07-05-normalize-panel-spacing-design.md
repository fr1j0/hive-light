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

Adopt the Settings rhythm in `PanelContent.sessionList`:

1. Outer padding `8 → 12` — frame matches Settings.
2. Outer `VStack` `spacing: 4 → 10` — the header-divider and footer-divider
   gaps match Settings' airiness.
3. Header: drop `.padding(.top, 4)`; keep `.padding(.horizontal, 10)` only.
   The uniform 12pt frame + 10pt spacing supply the top breathing room.
4. Footer: drop `.padding(.bottom, 2)`; keep `.padding(.horizontal, 10)` only.

The `SettingsPane` is not touched — it is already the target rhythm; the main
view moves to meet it.

### Horizontal note

The header/footer keep their extra `.padding(.horizontal, 10)` (so their
content sits at 12 + 10 = 22pt from the panel edge, indented past the session
cards). This is intentional and pre-existing — it is a horizontal concern,
orthogonal to the vertical airiness being normalized, and is left as-is.

## Out of scope

- Scroll-clamped list height (`scrolledListHeight = 480`) stays exactly as-is.
  It is a max height, unrelated to the padding rhythm.
- `SettingsPane` spacing (the reference) is unchanged.
- The `.frame(width: 340)` panel width is unchanged.

## Testing & verification

- No logic change → the existing 279-test suite must pass unmodified
  (`swift test`). No new unit tests; this is pure view spacing with no
  view-snapshot harness in the repo.
- Manual verification (local build): flip between the session list and the
  Settings pane and confirm the header, footer, and both views now share one
  visual rhythm — no view reads as tighter or airier than the others. Check
  both the populated list and the empty ("No active sessions") state.
