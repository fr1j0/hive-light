# Privacy

**Claude Light collects nothing. Nothing leaves your machine.**

Claude Light is a local macOS menu-bar app. It has no backend, no servers, no analytics,
and no telemetry. It makes no network requests. The maintainer receives no data about you
or your usage.

## What data Claude Light touches, and where it stays

- **Session state files** (`~/.claude-light/sessions/`). The hook shim writes each Claude
  Code session's state (status, project directory, git branch, model, timing) to this
  folder, and the app watches it to drive the display. These files never leave your disk.
- **Claude Code settings** (`~/.claude/settings.json`). Read to detect whether the hooks
  are installed, and edited only when you click install or remove in the app.
- **Claude Code transcripts** (`~/.claude/projects/`). Read locally to show per-session
  detail such as the current model and pending questions. Read-only, never transmitted.
- **Notifications.** Optional needs-you notifications are posted through macOS Notification
  Center on your machine — they are not push notifications and involve no server.
- **Terminal focus.** Clicking a session focuses its terminal tab via local macOS
  automation (Accessibility/AppleScript). Nothing is read from your terminal beyond what
  is needed to find the right tab.

## What Claude Light does NOT do

- No telemetry, analytics, crash reporting, or usage tracking.
- No network requests of any kind.
- No accounts, no identifiers, no profiling.
- No auto-update — your installed version changes only when you update it (e.g. via
  Homebrew).

If a future feature ever needs network access, it will be strictly opt-in (off by
default) and documented here before it ships.

## Third parties

Claude Light observes state produced by Claude Code, which is governed by
[Anthropic's terms and privacy policy](https://www.anthropic.com/legal/privacy). Installing
via Homebrew is governed by [Homebrew's analytics policy](https://docs.brew.sh/Analytics).
Claude Light itself is not a party to either.

## Contact

Claude Light is open source (Apache-2.0). Questions or concerns:
[github.com/fr1j0/claude-light/issues](https://github.com/fr1j0/claude-light/issues).
