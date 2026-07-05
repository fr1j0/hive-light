# Subagent Progress & Record — Design

## Problem

The panel shows only the *active* subagent of a parallel fan-out. As each
`Task`/`Agent` completes, its row vanishes (`SubagentDetection.swift` drops
any subagent with a successful `tool_result`). Two things are lost:

1. **Progress signal.** You glance and see "1 running" — you can't tell whether
   that's 1-of-2 or 1-of-8, so you have no sense of how far along the fan-out is.
2. **The record.** You can't see *which* agents already finished; completed work
   leaves no trace until the whole batch is gone.

This feature restores both: a durable `X of N done` count and a struck-through
record of completed agents, scoped to the current fan-out.

## Non-goals

- **No "pending" state.** The transcript only records *dispatched* subagents
  (a `Task`/`Agent` tool_use block). An un-dispatched, planned subagent leaves
  no trace in the JSONL, so a three-state `☑ done / ◼ active / ☐ pending`
  checklist (as in Claude Code's TodoWrite tracker) is not derivable from our
  data source. We surface only what the transcript knows: running, done, failed.
- **No cross-prompt history.** The record is not a permanent log; it clears at
  the next user prompt (see Semantics).

## Denominator: the since-last-prompt batch

`X of N` counts the subagents of the **current fan-out** — those belonging to
the work since the last real user prompt — not every subagent the session ran
all day. A session that ran 5 agents an hour ago and just dispatched 3 more
shows `1 of 3`, not `6 of 8`. The real-user-prompt boundary already present in
the scanner is the batch boundary.

## Semantics (`SubagentDetection.swift`)

### `Subagent.State`

Add `.done`:

```
enum State { case running, done, failed }
```

### Batch scoping — clear *settled* agents at each real user prompt

Today the user-prompt boundary clears only *failed* agents, deliberately keeping
*running* ones alive (a queued message can land while work is still in flight).
Extend it to clear both **done and failed** — any agent with a `tool_result` is
settled history. Running agents still carry across the prompt, preserving the
queued-message case.

Consequences:
- Mid-fan-out, the count reflects only this prompt's batch.
- If a queued user prompt lands *mid-turn* while agents are still running, the
  settled (done + failed) agents from before it clear, so the count re-bases on
  the new sub-batch — the same "your next prompt is the ack" principle already
  used for failures.

**Visible lifetime — turn-end, not next-prompt.** `SessionWatcher.reload()`
computes subagents only for sessions with `status == .running` (line 140); this
feature does **not** change that. So the block is live during the fan-out (the
count climbs `0 → 5 of 5`) and stays through the main agent wrapping up the
turn, then disappears when the turn ends and the session goes idle. The
clear-on-prompt rule above still governs the *within-turn* queued-prompt case;
the post-turn idle lingering (record visible until the next prompt) is
explicitly out of scope. This keeps the scan cost unchanged (running sessions
only) at the cost of the record not surviving turn-end.

### Emit done agents

Completed agents are no longer dropped. `visible` now includes `.done` rows
alongside `.running` and `.failed`.

### Ordering

**Dispatch order, stable.** A completing agent is struck through *in place*; the
list never reorders under the cursor. Matches the terminal's behavior.

### Counts on `SubagentList`

`SubagentList` carries every agent in the batch (in dispatch order) plus the
batch totals:

```
struct SubagentList {
    let visible: [Subagent]   // ALL agents, dispatch order — no cap
    let total: Int            // N — all agents in the batch
    let doneCount: Int        // X — settled-successful in the batch
    let failedCount: Int      // for the "· K failed" annotation
}
```

## Show all — no cap

**Every subagent is shown**, whatever its state (running / done / failed). The
row cap was tried during live testing and rejected: hiding completed agents
behind a `+K done` counter defeated the point — you want to *see* the record
build, not a number. So there is no data-level cap; `visible` is the whole
batch.

Large fan-outs are bounded in the **view**, not the data (see Rendering): past
~8 rows the block scrolls internally so the card can't balloon, but every agent
stays reachable.

## Rendering (`SubagentRows` in `SessionCard.swift`)

### Collapsed chip

Shown when the block is collapsed (the block still defaults to *expanded*, as
today — `subagentsCollapsed = false` is unchanged). Replaces today's
`⑂ 4 subagents`. The `⑂` fork glyph is dropped — it has no glyph in the system
font and rendered as a broken placeholder:

- `3 of 5 done`
- with failures: `3 of 5 done · 1 failed`

### Expanded rows (dispatch order, stable in place)

| State   | Mark             | Style                                                                       |
|---------|------------------|-----------------------------------------------------------------------------|
| done    | `✓` pale green   | `PanelPalette.green.opacity(0.7)` tick + `.tertiary` strikethrough label    |
| running | orange pulse dot | `.secondary` — brighter than done, so live work reads against the struck tail |
| failed  | `✗` red          | `PanelPalette.red` (as today)                                               |

The done tick is **pale green** (a muted success hue, pairing with the red `✗`
for failures) while the label stays dimmed/struck so the settled record reads
quietly. The running row's pulse dot is a small `PanelPalette.orange` circle
with a gentle pulse, honoring `prefers-reduced-motion` (static fallback) — the
one animated element, marking *which* agent is live.

**Bounding large fan-outs:** the expanded rows lay out inline up to
`maxInlineRows` (8). Beyond that the block is wrapped in a `ScrollView` with a
fixed height (~8 rows) so it scrolls internally rather than growing the card.
The height is set *explicitly* — a bare ScrollView collapses the panel's
ideal-height sizing.

The expanded header keeps the `X of N done` count visible above the rows so the
progress signal is present whether collapsed or expanded.

## Testing

Unit tests target `subagents(fromTranscript:)` — pure function over JSONL:

- **Counts:** batch of 5 with 3 done, 2 running → `total 5, doneCount 3`.
- **Done emitted:** a completed agent appears as a `.done` row (previously
  dropped).
- **Batch scoping:** agents settled before the last real user prompt are cleared
  from the count; a running agent carried across a queued prompt survives.
- **Denominator reset:** old-batch done + new-batch dispatch → count reflects
  only the new batch (`1 of 3`, not `6 of 8`).
- **Show all:** a 10-agent mixed batch returns all 10 rows in dispatch order; a
  20-agent batch returns all 20 (no cap, no overflow fields).
- **Stable ordering:** rows stay in dispatch order as agents complete.
- **Fail-safe:** unparseable lines skipped (existing guarantee preserved).

Existing `SubagentDetection` tests are updated for the new `.done` state and the
extended clear-on-prompt rule.

## Files touched

- `Sources/ClaudeLightCore/SubagentDetection.swift` — `.done` state, batch
  scoping, counts (no cap — all agents returned)
- `Sources/ClaudeLightApp/SessionCard.swift` — `SubagentRows`: chip, per-state
  rows, pale-green tick, internal scroll past 8 rows
- `Sources/ClaudeLightApp/PanelContent.swift` — panel-height estimate (caps a
  scrolled block's contribution)
- Chip text helper (`subagentChipText`) — `X of N done` format, no glyph
- Corresponding test files
