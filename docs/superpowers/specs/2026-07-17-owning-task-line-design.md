# Owning-Task Line — Design

## Problem

The session card shows the current subagent fan-out ("3 of 3 done" plus rows)
but not *what the fan-out is for*. In a task-driven session (Claude Code's
TaskCreate/TaskUpdate tracker), the terminal shows "■ Task 6: AGENTS.md docs +
quality gate … +2 completed" while the panel offers no hint of which task owns
the running agents or how far the task list has progressed. A glance at the
panel answers "how many agents?" but not "working on what?".

This feature adds one line of task context above the subagent group:

```
● feat/AT-5163-persist-canvas-com…   ▮▮▮  5s
  ▸ Task 6: AGENTS.md docs + quality gate · 5/7
    ∨ 3 of 3 done
      ✓ R̶e̶v̶i̶e̶w̶ ̶T̶a̶s̶k̶ ̶5̶ ̶(̶s̶p̶e̶c̶ ̶+̶ ̶q̶u̶a̶l̶i̶t̶y̶)̶
      …
```

## Non-goals

- **No full task list in the panel.** The terminal already renders it; the
  card shows only the in-progress task and a completed/total count. (Option
  considered and rejected: mirroring every pending/completed task row — the
  card gets tall on long lists and duplicates the terminal.)
- **No new toggle.** The existing switch governs this line too (see Settings).
- **No cross-window completeness guarantee.** Detection reads the same 4 MB
  wide tail as subagent scanning; a task list whose last snapshot and all
  mutations predate the window is invisible. Accepted, same as subagents.

## Data source (transcript JSONL)

Three shapes, all verified against a real multi-agent transcript (ai-agent-hub,
2026-07-17):

1. **`task_reminder` attachment** — periodic full snapshot of the task list:
   `{"type":"attachment","attachment":{"type":"task_reminder","content":[
   {"id":"1","subject":"Task 1: …","activeForm":"…","status":"completed",…},…],
   "itemCount":N}}`. Statuses seen: `pending`, `in_progress`, `completed`.
   Reminders with `itemCount: 0` carry no list and are ignored.
2. **`TaskCreate` tool_result** — `"Task #7 created successfully: <subject>"`.
   The id and subject are parsed from the result text (the tool_use input has
   the subject but no id).
3. **`TaskUpdate` tool_use input** — `{"taskId":"3","status":"in_progress"}`.
   Only status changes are replayed; other TaskUpdate fields are ignored.

## Semantics (new `TaskSummaryDetection.swift` in HiveLightCore)

`taskSummary(fromTranscript:) -> TaskSummary?` where

```swift
struct TaskSummary: Equatable, Sendable {
    let inProgressSubject: String   // most recently updated in-progress task
    let doneCount: Int
    let total: Int
}
```

- **Base + replay.** The latest *populated* `task_reminder` snapshot is the
  base state; `TaskCreate` results and `TaskUpdate` status changes appearing
  *after* it are replayed on top (creates append as `pending`; updates set the
  status of a known id, unknown ids are ignored). A transcript with creates/
  updates but no reminder yet builds state purely from replay.
- **Returns nil** when no task state exists or no task is `in_progress` —
  between tasks the line simply disappears; the card renders exactly as today.
- **Most recent wins.** If several tasks are `in_progress`, the one whose
  status changed last (by transcript order) is shown.
- **Defensive.** Unparseable lines are skipped; a malformed create-result or
  reminder entry never crashes the scan (same posture as SubagentDetection).

## Rendering (SessionCard / PanelContent)

One secondary-style line above the subagent group, present only for running
sessions when the toggle is on and `taskSummary` is non-nil:

- Text: `▸ <subject> · <doneCount>/<total>` — subject truncated to 40 chars,
  matching subagent-label truncation.
- Per the panel visual grammar: this is one new info kind with one type
  treatment, at a fixed position (between the session row and the fan-out
  group). It renders whether or not a fan-out is active — task context is
  useful even when the session works inline.

## Data flow (SessionWatcher)

`reload()` already does a memoized 4 MB wide read per running transcript for
subagents, keyed by (mtime, size). The cache entry widens to hold the pair
(`SubagentList`, `TaskSummary?`) computed from the same string in one read —
no additional I/O. A new `taskSummaryBySession` published map feeds the card,
alongside `subagentsBySession`.

## Settings

The existing "Show subagents" switch is relabeled **"Show session activity"**
and governs both the task line and the subagent rows. The defaults key stays
`showSubagents` — no migration, existing installs keep their choice.

## Testing

TDD throughout, fixture shapes lifted from the real transcript:

- Reminder-only snapshot → summary (in-progress subject, counts).
- Replay: create-after-snapshot appends; update-after-snapshot changes status;
  update to `completed` of the last in-progress task → nil.
- No reminder, replay-only state → summary.
- Multiple in-progress → most recently updated wins.
- Unknown taskId update, malformed create text, empty reminder → ignored.
- Truncation of long subjects (40 chars).
- Panel/card: line renders above fan-out; hidden when summary is nil or the
  toggle is off.
- Scratch-verify against the live ai-agent-hub transcript before shipping.
