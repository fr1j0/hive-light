# Task progress bar + usage-strip blues

**Date:** 2026-07-18
**Status:** Approved

## Problem

Two adoptions from the 2026-07-18 panel mockup review (artifact: "Panel —
fresh ideas, refined", variant 1 + the recolor):

1. The current-task line states progress only as text (`· 4/8 tasks`);
   a shape channel would make it readable at a glance.
2. The bottom usage strip's bars speak urgency (white → orange ≥75% →
   red ≥90%). The user chose the mockup's calmer look: shades of one
   blue, always — the % number and reset countdown carry all urgency.

A brainstorm on the strip's semantics concluded: keep them. Each row
stays "% of bucket used + its reset countdown" (5-HOUR rolling window,
ALL weekly, FABLE's tighter weekly sub-cap). No relabels, no pace
projection, no row changes.

## Behavior

### Task progress bar

- A 2pt-tall, 1pt-radius bar renders directly under the current-task
  row inside `TaskBlock`, left-inset 12pt (aligning with the task text,
  clearing the 7pt ■ marker + 5pt gap).
- Fill fraction = `doneCount/total` (0 total never occurs; guard to 0).
- Fill: `PanelPalette.orange` at 0.75 opacity — the current-task
  marker's color. Track: `Color.primary.opacity(0.12)`.
- No percent label anywhere. The `· done/total tasks` text is unchanged.
- Renders whenever the current-task row renders (every TaskBlock).
- Fraction computed by a pure core helper:
  `public func taskProgressFraction(_ summary: TaskSummary) -> Double`
  in `PanelModel.swift`, clamped to 0...1, unit-tested.

### Usage strip blues

- In `UsageRow.limitLine`, the fill color stops using
  `UsagePalette.urgency(...)`. Each row's fill is a fixed blue chosen
  by ROW INDEX in the displayed limits array — a depth ladder:
  - index 0: `#8FB7D9` (light steel)
  - index 1: `#5A96D6` (mid)
  - index ≥2: `#2F6FC4` (deep) — extra scoped buckets clamp here.
- Exposed as `UsagePalette.bucketBlue(rowIndex: Int) -> Color`.
- The bars never change hue with utilization ("blue always" — user's
  explicit call, alarm dropped knowingly). `%` text and countdown are
  untouched and now carry all urgency.
- `UsagePalette.urgency(_:)` itself stays — `UsageView` (the
  click-through) keeps its current coloring; restyling it is a separate
  decision out of scope here.

## Code changes

- `Sources/HiveLightCore/PanelModel.swift`: add `taskProgressFraction`.
- `Sources/HiveLightApp/SessionCard.swift` (`TaskBlock`): bar under the
  current-task HStack.
- `Sources/HiveLightApp/UsageRow.swift`: `bucketBlue(rowIndex:)` in
  `UsagePalette`; `limitLine` takes its row index and uses it.
- Tests: `taskProgressFraction` cases (0 done, partial, all done).

## Out of scope

- UsageView bar colors.
- Any change to bucket labels, ordering, or the fetch.
- The local-fallback microbar (model-identity colors) — untouched.
