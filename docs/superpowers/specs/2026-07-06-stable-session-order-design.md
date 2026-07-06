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

## Sort setting — two stable orders

Live discussion surfaced a second real mental model ("A, B, A should read
A, A, B"), so Settings gains **"Sort sessions"** (radio): **By project**
(default) / **Opened**. Both obey the stability law — status never moves
anything; the only movement is insertion when the user opens a session.

- **Opened** — pure chronological (terminal-tab order), as above.
- **By project** — *grouped chronological*: blocks ordered by their earliest
  session's start; sessions within a block chronological.
- **Group identity = `repo_root` ?? `cwd` — never the name** (basename
  collisions must not merge unrelated projects). `repo_root` is the MAIN
  checkout's root: subdirectory sessions and **worktree** sessions (gitdir
  pointer resolved) cluster with their parent repo. The hook persists it
  alongside `branch` (same walk, refreshes with cwd, nil for non-repos).
- Urgency is NOT an option — it was the disease, not a preference.

**Grouped render (mockup variant B, chosen over rail/tray/fused/project-card
alternatives):** a block of 2+ sessions gets a tiny uppercase repo header
(`blockTitle` — the repo directory's name, never a worktree folder's), and
its cards lead with the **branch** (`groupedCardTitle`: branch ?? project,
plus a dim `· <dir>` locator for sessions outside the repo root); the
branch-only subtitle is suppressed (it moved into the title). Singleton
blocks render classic, untouched — with every project single-sessioned the
grouped panel is pixel-identical to the flat one; chrome appears only when
it disambiguates. Rejected on live/mockup review: connecting rails (reads
as status color or over-nests against subagent rails), group trays (third
background level), fused/project cards (restyle the session line
inconsistently between grouped and singleton contexts).

## Start time — schema addition

`Session` gains optional `started_at`:

- The **hook** sets it when it creates the session's file and **preserves**
  it on every later write — the same sticky-field merge `branch` and `model`
  already use in `ApplyHook` (`?? existing?.startedAt`, with `now` when no
  existing session).
- **Fallback** for files written by an older hook (nil `started_at`): sort as
  **distant past, id tie-break** — stability trumps correct order (an
  `updatedAt` fallback would keep shuffling on every event, recreating the
  bug during transition). Un-stamped sessions clump stably at the top;
  self-heals as the new hook stamps each session on its next event.
- Compatibility: old app ignores the unknown key; new app + old hook uses the
  fallback. No break in either direction.

## What changes, what doesn't

| Surface | Change |
|---|---|
| `sortedForMenu` | urgency rank removed → `SessionOrder` param: `.project` (grouped, default) / `.opened` (chronological) |
| `Session` / hook (`ApplyHook`) | `started_at` field (set-once merge) + `repo_root` (branch-like refresh) |
| Settings | "Sort sessions" radio: By project (default) / Opened |
| Dots, timers, subtitles, notifications, summary counts, traffic light | unchanged — urgency stays fully visible, just not positional |

## Tests

- Ordering: mixed statuses stay chronological; status flips don't reorder;
  tie-break deterministic; nil `started_at` falls back to `updatedAt`.
- Merge: `started_at` set on first write, preserved across subsequent events
  (including events that omit cwd/transcript), unchanged by status flips.
- Live gate: a multi-session afternoon — rows never move while the panel is
  open; new sessions appear at the bottom; clicking lands the right terminal
  every time.
