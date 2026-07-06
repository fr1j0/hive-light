# Stable Session Order — Design

## Problem

`sortedForMenu` ranks rows by urgency (`error → attention → waiting → handoff
→ running → idle`), and the panel re-sorts live while open. Every status flip
moves rows: with 6 active sessions the list is in near-constant motion, each
shuffle forcing a full re-scan even of familiar names — and rows sometimes
shift **mid-click**, focusing the wrong terminal.

**Why urgency sort is a relic:** it dates from when the list was a *triage
read* ("the top row is what needs me"). Since click-to-focus landed, the list
is a **navigation index** — click a row, land in its terminal tab. Indexes,
like tab bars, must hold still. Urgency's remaining duty (what needs you) is
carried by the dot colors, bold red timers, notifications, the summary line,
and the traffic light itself — none of which need position.

## Ordering rule

Sessions sort by **start time, ascending** — oldest at top, mirroring the
order terminal tabs were opened. Tie-break: `sessionID` (deterministic).

- **Status changes never move a row.** A session turns red in place — the
  same law the subagent rows follow ("struck through in place, never reorders
  under the cursor").
- **New sessions append at the bottom** — every existing row's absolute
  position is untouched (newest-on-top would push all memorized positions
  down one).
- **Expired sessions drop out**; rows close up. Removal, not reordering.

No sort setting (YAGNI): with urgency sort retired as a *mistake* rather than
a preference, the only alternative stable order (group by project) has no
demonstrated demand. Add later if live use creates the itch.

## Start time — schema addition

`Session` gains optional `started_at`:

- The **hook** sets it when it creates the session's file and **preserves**
  it on every later write — the same sticky-field merge `branch` and `model`
  already use in `ApplyHook` (`?? existing?.startedAt`, with `now` when no
  existing session).
- **Fallback** for files written by an older hook (nil `started_at`): sort by
  `updatedAt`. Transitional; self-heals as sessions cycle within hours.
- Compatibility: old app ignores the unknown key; new app + old hook uses the
  fallback. No break in either direction.

## What changes, what doesn't

| Surface | Change |
|---|---|
| `sortedForMenu` | urgency rank removed → `started_at` ascending, id tie-break |
| `Session` / hook (`ApplyHook`) | `started_at` field, set-once merge |
| Dots, timers, subtitles, notifications, summary counts, traffic light | unchanged — urgency stays fully visible, just not positional |
| Settings | unchanged (no sort knob) |

## Tests

- Ordering: mixed statuses stay chronological; status flips don't reorder;
  tie-break deterministic; nil `started_at` falls back to `updatedAt`.
- Merge: `started_at` set on first write, preserved across subsequent events
  (including events that omit cwd/transcript), unchanged by status flips.
- Live gate: a multi-session afternoon — rows never move while the panel is
  open; new sessions appear at the bottom; clicking lands the right terminal
  every time.
