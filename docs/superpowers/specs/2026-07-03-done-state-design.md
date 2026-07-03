# Brief "done" state for ended sessions (#54)

## Problem

Sessions vanish from the dropdown the instant `SessionEnd` fires. The
completion moment — often exactly what the user is waiting for — is
invisible; work silently disappears.

## Goal

A finished session lingers briefly as a greyed-out, non-interactive row
with a checkmark ("done · 40s ago") before dropping off. The done state
must not affect the aggregate light, counts, or notifications.

## Design

### Tombstone on disk (chosen approach)

`SessionEnd` writes the session file with a new status instead of deleting
it. The file is the single source of truth, consistent with all other
state; it survives app restarts and is trivially testable.

Rejected alternative: app-side memory of recently-deleted sessions — no
schema change, but state is lost on restart, only works when the app
observed the delete, and adds racy bookkeeping to `SessionWatcher`.

### Data model & hook mapping

- `SessionStatus` gains a `done` case (raw value `"done"`).
- `action(for:)` maps `"SessionEnd"` to `.set(.done)` — `updatedAt`
  stamps the end time, and the `.set` path in `applyHook` preserves the
  captured terminal identity as with any other status write.
- `HookAction.delete` and the corresponding `applyHook` branch are
  removed: nothing produces them once `SessionEnd` sets a status.
  `SessionStore.delete` itself stays — the app's linger cleanup uses it.

### Linger window & cleanup

- New Core constant `doneLingerWindow: TimeInterval = 120` (2 minutes,
  the top of the issue's 1–2 minute range).
- A pure Core function partitions done sessions by age against the
  window: `expiredDoneSessions(_ sessions: [Session], now: Date,
  linger: TimeInterval = doneLingerWindow) -> [Session]` returns the
  done sessions whose `updatedAt` is older than the window.
- In `SessionWatcher.reload()`, expired done sessions get their files
  deleted via `SessionStore.delete` and are dropped from the display;
  younger done sessions render as rows.
- No new timers: the existing 30-second stale timer already re-runs
  `reload()`, so a done row lives 120–150 s in practice.
- Fallback: if the app isn't running, the existing 8-hour
  `SessionStore.prune` TTL sweeps orphaned tombstones (decodable files
  prune by `updatedAt`, which the done write refreshed).

### Aggregate, counts, and visibility — "as if absent"

- Done sessions are excluded from the inputs to `aggregateLight`,
  `aggregateNeedsAttention`, `statusCounts`, and `summaryText`. With only
  done sessions present, the light and header behave exactly as with no
  sessions.
- The exclusion happens at the call sites in the app (filter before
  computing light/counts); done rows are appended to the menu list only.
- `visibleSessions` additionally hides done + headless sessions (same
  noise rationale as idle headless: nothing to reach, nothing pending).
- `sortedForMenu` ranks `done` last (rank 6, after `idle`).

### Row presentation

- Greyed-out (secondary) text, checkmark icon, status text
  "done · 40s ago" using the existing relative-time formatting; the age
  refreshes when the 30 s stale timer republishes the session list, so it
  can lag up to ~30 s in an open menu.
- Non-interactive: no focus action and no hover affordance — the
  terminal may already be gone.

### Notifications

No changes: `done` is not a needs-you status, so `needsYou(_:)` returns
false and `newlyNeedingYou` never selects the transition. A test pins
this (running → done produces no notification candidates).

### Compatibility

- Old app + new hook: decoding `"done"` throws, `SessionStore.load`
  returns nil, session invisible — indistinguishable from today's
  post-delete behavior.
- New app + old hook: `SessionEnd` still deletes the file; the feature is
  simply absent. No migration needed.

## Testing

TDD in `ClaudeLightCore` tests:

- Hook mapping: `SessionEnd` → `.set(.done)`; the tombstone write
  preserves terminal identity fields.
- Linger partition: done younger than window kept; older returned as
  expired; non-done sessions never expire this way regardless of age.
- Aggregate/counts: done excluded — only-done input yields the no-session
  light and nil summary at the call-site filter level.
- Sort: done ranks after idle.
- Visibility: done + headless hidden; done + reachable visible.
- Notifications: running → done yields no `newlyNeedingYou` entries.

App-side row styling follows the existing row-view pattern (visual,
covered by the existing UI conventions rather than unit tests).

## Out of scope

- Configurable linger duration.
- A "done" count in the dropdown header summary.
- Any notification on completion (could be a future opt-in, not now).
