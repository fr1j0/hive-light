# Settings Pane Redesign (Variant B) — Design

## Problem

The settings pane is the one surface still speaking stock AppKit while the
rest of the panel speaks its own grammar. Stock blue checkboxes are the only
unsanctioned color in the app (color law: red/orange/green = status, amber =
git refs, grey = structure). The page is a flat unsectioned list mixing
display toggles, behavior toggles, captions, and an action; captions float at
an 18pt indent aligned to nothing; controls lead their labels, opposite the
modern trailing-control idiom. The user's verdict: old fashioned, wrongly
visually architected, ugly.

## Chosen design — mockup variant B ("card groups · switches")

Approved from the three-variant mockup
(https://claude.ai/code/artifact/d9c90d4b-ed2d-4367-b6ef-90d39d88c38f).
Same seven settings, same flip-in-place navigation, no behavior changes.

- **Three titled card groups** — SESSIONS (sort, subagents), USAGE (usage
  stats, plan limits), GENERAL (launch at login, notifications) — plus a
  standalone **hooks-action card** at the bottom.
- **Section titles** are the panel's existing 9pt semibold uppercase
  kerning-1 treatment, tertiary (structure, not content — matching Usage
  view's section titles, not the grouped list's primary headers).
- **Cards** wear the session-card surface: 5% primary fill, 8pt corner
  radius. Rows inside are separated by inset hairlines (6% primary, inset to
  the row's content edge). Only the hooks card is clickable, so only it gets
  the 10% hover fill.
- **Rows**: 12pt label leading, control trailing. Captions (10pt tertiary)
  sit under their own label inside the card, wrapping in the label column —
  never under the control.
- **Custom monochrome controls** (stock styles tint system blue):
  - *Mini switch* — 26×15pt capsule; off = 16% primary track with light
    knob; on = 92% primary track with panel-background knob. Animated
    knob slide on toggle.
  - *Segmented sort control* — "By project | Opened" pill; 8% primary
    container, selected segment 18% primary at 10.5pt.
- **Disabled plan-limits row** (API-key/Bedrock logins, `hasOAuthLogin ==
  false`): row content at 40% opacity, explanatory caption stays in place
  (text swaps to the "Requires a Claude subscription login…" variant, as
  today).
- **Hook error** (`hookActionError`): unchanged red warning label, rendered
  below the hooks card.
- **Header**: unchanged (back chevron / centered title / hidden mirror).

## Implementation

- `Sources/ClaudeLightApp/SettingsPane.swift` — rebuilt body: section
  builder (title + card), row builder (label / caption / trailing control).
- New `Sources/ClaudeLightApp/PanelControls.swift` — `MiniSwitch(isOn:)`
  and `SegmentedPicker(selection:options:)` as reusable panel-native
  controls (Button-driven, no stock Toggle/Picker styles), plus the shared
  card-surface constants if extraction from SessionCard is cheap.
- Bindings on `SessionWatcher` are untouched; `launchAtLoginAvailable` /
  `notificationsAvailable` conditionals keep gating their rows; the GENERAL
  card renders only if at least one of its rows is available.
- Accessibility: MiniSwitch exposes `.toggle` traits/value, SegmentedPicker
  exposes selected state — parity with the stock controls they replace.

## Testing

View-layer only; no core logic changes. Existing 333 tests must stay green.
New pure logic worth a test: none anticipated (control state lives in
existing `@Published` bindings). Verification is the live-tune loop: build,
relaunch, compare against the mockup, adjust in tiny steps.

## Out of scope

Content rethink (wording, which settings exist), light-theme-specific
tuning beyond what the semantic styles (`.primary` opacities) give for free,
and any main-panel changes.
