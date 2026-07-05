# Settings in the header, footer rebalance (#109)

**Issue:** [#109 — Move Settings to the header's right corner, icon-only](https://github.com/fr1j0/claude-light/issues/109)
**Date:** 2026-07-05
**Scope:** `Sources/ClaudeLightApp/PanelContent.swift` only. View-layer change; no core logic touched.

## Goal

The Settings control moves from the panel footer to the trailing corner of the
header row, icon-only. The footer rebalances: app name + version take Settings'
old left slot, the power button stays at the right.

## Decisions

- **Always-on header.** The header row currently renders only when
  `watcher.summary` is non-nil (nil = zero live sessions), which would make
  Settings unreachable in the empty state. The header now renders
  unconditionally.
- **Empty-state header content: grey dot + idle text.** With zero sessions the
  header shows the status dot (the existing `headerColor` computed property
  already returns `Color.secondary` when no icon segment is lit) plus the text
  "No active sessions". The body's current "No active Claude Code sessions"
  empty-state row is removed — the header idle text replaces it, so the message
  is never shown twice.

## Design

### Header (always rendered)

```
● 2 running, 1 waiting                    ⚙︎
──────────────────────────────────────────
```

- `HStack(spacing: 8)`: `Circle().fill(headerColor)` 8×8 · summary text
  (`summary ?? "No active sessions"`, 12pt, `.secondary`) · `Spacer()` ·
  gear button.
- Gear button: `gearshape` system image only (no "Settings" text),
  `.buttonStyle(.plain)`, `.foregroundStyle(.secondary)`, same action as the
  old footer button (`showingSettings = true`, flipping the panel content to
  `SettingsPane` in place).
- Accessibility & discoverability: explicit `.accessibilityLabel("Settings")`
  (the text label is gone) and `.help("Settings")` hover tooltip.
- Hit target: the header is denser than the 11pt footer was, so the gear gets
  a `.frame(width: 22, height: 22)` plus `.contentShape(Rectangle())` so the
  whole 22×22pt area is tappable, not just the glyph.
- The `Divider()` below the header remains, now unconditional.

### Body empty state

`sessionRows` no longer renders the "No active Claude Code sessions" text.
With zero sessions it emits nothing; the outer `VStack(spacing: 4)` then puts
the header divider and footer divider a few points apart, reading as a quiet
empty band (approved in mockup review). If that double-rule looks heavy in the
live build, add a fixed ~6pt spacer in the empty case — a visual-check call,
not a design change.

### Footer

```
Claude Light v0.16.0  ⚠                  ⏻
```

- Left: `Claude Light vX.Y.Z` (11pt, `.tertiary`) moves from the right edge to
  the left, taking Settings' old slot.
- The hook-error warning triangle (shown when `watcher.hookActionError` is
  set) stays in the left cluster, beside the version text.
- `Spacer()`, then the power/quit button unchanged at the right edge.

## Testing & verification

- No core (`ClaudeLightCore`) changes → the existing test suite (276 tests)
  must pass unmodified. No new unit tests; there is no new logic to test —
  the `summary ?? "No active sessions"` fallback and layout moves are pure
  view composition.
- Manual verification (per prior panel work; tooltips cannot be exercised
  synthetically): local build, human check of both states —
  1. zero sessions: grey dot + "No active sessions" in header, gear reachable,
     no duplicate empty text in the body;
  2. active sessions: colored dot + summary, gear at top-right, footer shows
     name+version left / power right;
  3. gear hover shows the "Settings" tooltip; gear click flips to Settings.

## Out of scope

- Stats strip (#83), hook transcript cap (#106), any `SettingsPane` changes.
