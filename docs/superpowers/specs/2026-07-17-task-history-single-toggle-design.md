# Task history: single count-free toggle

**Date:** 2026-07-17
**Status:** Approved

## Problem

The owning-task block currently always shows the last 2 completed tasks as
struck rows, with a "+N earlier" disclosure for anything older. Two issues:

1. The "+N earlier" header stays visible (with its count) even when the
   history is expanded — the label is then wrong/redundant.
2. The always-visible struck pair and the hidden-count arithmetic add noise
   the user doesn't want. Completed tasks are history; they should tuck away
   as they finish.

## Behavior

- **All** completed tasks live under a single disclosure row, collapsed by
  default, rendered above the current-task line:
  - Collapsed: `▸ earlier tasks`
  - Expanded: `▾ earlier tasks` followed by every completed task, struck,
    in chronological order.
- No counts on the toggle in either state. The only remaining number is the
  existing `· done/total tasks` suffix on the current-task line.
- The toggle renders only when at least one task is completed. Zero done →
  no toggle row, just the current-task line.
- As a task completes it joins the group under the toggle: invisible when
  collapsed, appended to the list when the user has it expanded.
- Long histories keep the existing containment: up to 8 rows inline, then a
  fixed-height internal scroll (same cap and height as before).
- Visual treatment of every element is unchanged — chevron size/weight,
  tertiary label at 10.5pt, struck rows with dimmed green checkmarks, row
  spacing, animation timing.

## Code changes

- `Sources/HiveLightCore/PanelModel.swift`
  - Replace `taskHistoryOverflowText(_:) -> String?` with
    `taskHistoryToggleText(_:) -> String?`: returns `"earlier tasks"` when
    `doneSubjects` is non-empty, else `nil`.
  - Delete `taskHistoryVisibleCount`.
- `Sources/HiveLightApp/SessionCard.swift` (`TaskBlock`)
  - Remove the always-visible `suffix(taskHistoryVisibleCount)` rows.
  - The disclosure wraps the full `doneSubjects` list; inline/scroll split
    unchanged (`maxInlineRows = 8`, `scrollBlockHeight = 128`).
  - Header comment updated to describe the new grammar.
- Tests: update `taskHistoryOverflowText` cases to the new function and
  semantics (nil at zero done, label at ≥1, never a count); drop
  visible-count assertions.
- `README.md`: session-activity panel description reflects the single
  toggle (no "last two struck rows", no "+N earlier").

## Out of scope

- Subagent block ("N of M done" chip) — untouched.
- Persistence of the expanded/collapsed state across panel opens — stays
  per-card `@State` as today.
