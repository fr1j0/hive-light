# Needs-You Notifications — Design

**Date:** 2026-07-03 · **Issue:** #46

## Problem

The menu-bar light only helps when the user is looking at it. In another Space,
a full-screen app, or a second display, a session flipping to red goes unseen
until the user happens to glance up. The result is exactly what Claude Light
exists to prevent: an agent blocked on input for minutes.

## Decision

Post a native macOS notification when a session *transitions into* a needs-you
state. Strictly opt-in, local-only, and click-to-focus.

## Behavior

- **Toggle.** A "Notify when a session needs you" checkbox row in the dropdown,
  persisted in `UserDefaults` (`notifyOnNeedsYou`), default **off**. Turning it
  on requests `UNUserNotificationCenter` authorization (alert + sound).
- **Trigger.** A session counts as needing you in `waiting`, `attention`,
  `handoff`, or `error`. A notification fires when a session enters one of
  those states from a non-needs-you state, or first appears already in one.
  Moving *between* two needs-you states (e.g. `attention` → `waiting`) does
  not re-notify.
- **Baseline.** The first reload after launch records state without notifying,
  so restarting the app never replays already-red sessions.
- **Identity.** The notification identifier is the session ID: a newer alert
  for the same session replaces the older one instead of stacking.
- **Content.** Title is the project name; body is the friendly status label
  (for `error`, including the reason, e.g. "API error: overloaded").
- **Click.** Activating the notification focuses the session's terminal via
  the existing `TerminalFocuser`.
- **Availability.** `UNUserNotificationCenter` requires a real app bundle;
  unbundled dev builds hide the row (same gate as launch-at-login).

## Architecture

- `ClaudeLightCore/NeedsYouDetection.swift` (pure, tested):
  - `needsYou(_ status: SessionStatus) -> Bool`
  - `newlyNeedingYou(previous: [String: SessionStatus], current: [Session]) -> [Session]`
- `ClaudeLightCore/MenuModel.swift`: `friendlyStatusLabel(for:)` promoted from
  `MenuContent`'s private helper so menu rows and notification bodies share
  one wording.
- `ClaudeLightApp/SessionNotifier.swift` (glue, untested like `TerminalFocuser`):
  wraps `UNUserNotificationCenter` — authorization, posting, banner-while-active
  presentation, and the activation delegate that resolves a session ID back to
  a live session and focuses it.
- `SessionWatcher`: keeps the previous reload's `[sessionID: status]` map;
  after each reload (post error-detection, so `error` transitions count),
  passes it through `newlyNeedingYou` and posts for each hit. The map updates
  every reload regardless of the toggle so enabling mid-run doesn't replay
  old transitions.

## Error handling

All notification-center calls are fire-and-forget with denied-authorization
treated as "the user said no": the toggle stays available, posts simply don't
land. No polling, no network — unchanged principles.

## Testing

Core transition logic and label mapping are unit-tested (TDD). The
notification-center and delegate glue is thin system-API code, verified
manually from a packaged build.
