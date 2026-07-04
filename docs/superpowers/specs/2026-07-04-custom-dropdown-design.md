# Custom dropdown panel (#86)

## Problem

The system menu (`menuBarExtraStyle(.menu)`) constrains the UI: menus
coerce images to monochrome templates (workarounds live throughout
`MenuContent`), rows can't have second lines, hover states, live timers,
or custom layout — and the roadmap (#81 timers, #82 branch labels, #83
stats) pushes against every one of those limits. Issue #86 asked for a
spike; the design below is its **go** decision.

## Decision drivers (spike findings)

- `.window` style gives a real SwiftUI view hierarchy: full styling,
  multi-line rows, hover, animation — no template-image coercion.
- Outside-click dismissal, Escape, and screen-edge positioning are
  framework-provided for `.window` MenuBarExtra content on macOS 13+
  (our existing floor).
- What a native menu gave for free and the panel must compensate for:
  VoiceOver semantics (explicit accessibility labels/traits per card)
  and keyboard navigation (dropped — a glance-and-click surface; the
  notification remains the no-mouse path).
- The menu-bar icon, its animation clock, and `SessionWatcher` are
  untouched — this is a pure presentation-layer swap.

## Scope

This project ships the panel shell, session cards, elapsed-state timers
(derivable from existing data), done rows, collapsible subagent rows,
in-place settings, and footer. Reserved slots, filled by later projects:
branch labels in the card title (#82 — needs hook changes) and the
stats strip above the footer (#83 — needs a transitions log).

## Layout (validated via mockups, option B "cards")

Mockups: `.superpowers/brainstorm/35217-1783177759/content/` (layout.html,
subagents.html — git-ignored, kept locally).

Panel ≈ 340 pt wide, dark/light adaptive (system materials):

1. **Header** — colored dot + the existing `summaryText` ("1 needs you ·
   1 working"). Hidden when nil, exactly like today.
2. **Session cards**, sorted by the existing `sortedForMenu`:
   - Top line: status dot (existing lamp colors) · bold project name
     (existing `displayName`) · right-aligned elapsed-state timer.
   - Second line (needs-you and running states): `session.detail` when
     present (the pending question / permission message), otherwise
     `friendlyStatusLabel`; single line, tail-ellipsized. Error rows show
     the "API error: …" reason here (red-tinted).
   - Whole card clickable → `TerminalFocuser.focus(session)`; hover
     highlights the card; no explicit Focus button.
   - **Done sessions**: flat grey row (checkmark + "project — done · 40s
     ago"), not a card, non-interactive — same semantics as today.
3. **Subagent rows** (when the global "show subagents" setting is on and
   the session has any): nested inside the parent card behind a per-card
   disclosure chevron.
   - Expanded: mini-rows with the subagent label and state; failed rows
     red with an ✕; the existing overflow cap renders "+N more running".
   - Collapsed: one compact chip — "⑂ N subagents" with " · M failed"
     red-highlighted when M > 0.
   - Default expanded; collapse state is per-session and in-memory only
     (resets on relaunch; not persisted — YAGNI).
4. **Stats slot** — a divider where #83's strip will dock; renders
   nothing in this project.
5. **Footer** — Settings (gear), version string, Quit.

### Timers

Elapsed state time = `now - updatedAt`, formatted by the existing
`relativeTime`. Needs-you timers tint red. A `TimelineView`-driven
1-second tick runs only while the panel is open, so ages read live with
zero background cost (fixes the 30-second staleness the menu had).

### Settings

The gear flips the panel content in place to a settings pane (back
control at top): the same four actions as today's submenu — show
subagents, launch at login, needs-you notifications, install/remove
hooks (with the existing installed-state and error feedback). No nested
popovers, no separate window.

## Code shape

- `ClaudeLightApp.swift`: `.menuBarExtraStyle(.menu)` → `.window`;
  content view swapped.
- New `Sources/ClaudeLightApp/PanelContent.swift` (top-level layout +
  settings flip), `SessionCard.swift` (card + done row + subagent
  nesting), `SettingsPane.swift`. `MenuContent.swift` is **deleted**
  along with its NSImage dot/triangle/template workarounds — SwiftUI
  views style colors directly in a `.window` panel.
- Pure presentation derivations move to Core as testable functions in a
  new `Sources/ClaudeLightCore/PanelModel.swift`:
  - `cardTitle(for:) -> String` (project name; branch appended here when
    #82 lands),
  - `cardSubtitle(for:errorReason:) -> String?` (detail ?? label; error
    formatting; nil for done),
  - `timerText(for:now:) -> String` (relativeTime wrapper),
  - `subagentChipText(_ list:) -> String` ("⑂ 3 subagents · 1 failed"),
  - `accessibilityLabel(for:) -> String` (the old menu row string —
    "project — status", preserving VoiceOver parity).
- `SessionWatcher`, `IconModel`, hook side: unchanged.

## Error handling

- Focus failures stay fail-safe (`TerminalFocuser` already is).
- A session with unparseable pieces renders from whatever fields decode
  (existing fail-safe load behavior).
- If the panel content ever fails to lay out (empty state), the
  "No active Claude Code sessions" line renders as today.

## Testing

- TDD in Core for every `PanelModel` function (title, subtitle
  precedence incl. error > detail > label and done → nil, timer text,
  chip text singular/plural/failed, accessibility label).
- `swift build` gates the SwiftUI layer.
- E2E: signed-build swap (as in the notification demo) with fake session
  files covering: needs-you with question + timer, running with
  subagents (expand/collapse, failed), done row, empty state, settings
  flip, click-to-focus, outside-click dismiss. Screenshots feed
  README/#85.

## Out of scope

- Branch labels (#82), stats strip (#83) — reserved slots only.
- Keyboard navigation inside the panel.
- Persisting per-card collapse state.
- Any change to icon, notifications, hook, or session schema.
