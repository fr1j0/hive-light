# Hide Temp-Dir Sessions — Design

## Problem

Tooling (plugin jobs, statusline scripts, headless `claude -p` sidecars) spawns
Claude Code sessions with `cwd` in the system temp area. They render as
"temp / running" cards — unclickable, branchless, meaningless — and worse,
they count toward "N working" and drive the traffic light orange. Three of
them at once turned "1 real session working" into "4 working."

The existing noise filter (`HeadlessSessions.swift`, #64) drops headless
sessions only when *idle*; a running headless one still shows. That judgment
predates today's constant short-lived background runs.

## Rule

A session whose `cwd` is inside the system temp area is machinery, not work:
**never a card, never counted, never lights the lamp — regardless of status.**

Temp area = `/tmp`, `/var/folders` (macOS `$TMPDIR` lives there), and their
`/private` twins. Prefix match on the normalized path; stable macOS facts, no
env reads, so the predicate stays pure and testable.

## Unchanged

- Project-dir headless sessions keep today's behavior: visible while running
  (marked `(background)`), dropped when idle. Deliberate `claude -p` jobs in
  real project directories stay visible.
- No settings toggle (YAGNI — nobody wants temp rows back).

## Accepted edge

Genuinely working in `/tmp/scratch` makes the session invisible. Deliberate:
the temp dir is the signal.

## Implementation

- `Sources/ClaudeLightCore/HeadlessSessions.swift`:
  - `public func isTempDirSession(cwd: String) -> Bool` — normalized prefix
    match against the four roots.
  - `visibleSessions(_:)` additionally filters `isTempDirSession` — this is
    the existing choke point feeding rows, counts, and the aggregate light.
- Tests (`HeadlessSessionTests.swift`): all four roots match (running AND
  idle), project paths and `.claude/worktrees` paths don't, empty cwd
  doesn't, existing idle-headless drop still holds, mixed-list filtering.
