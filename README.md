<p align="center">
  <img src="assets/app-icon.png" alt="Claude Light" height="150">
</p>

<h1 align="center">Claude Light</h1>

<p align="center">A native macOS menu-bar traffic light for your Claude Code sessions — see what needs you, at a glance.</p>

<p align="center">
  <a href="LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache_2.0-blue?style=for-the-badge"></a>
  <img alt="Platform: macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-000000?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Swift 5.9+" src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=for-the-badge&logo=swift&logoColor=white">
  <a href="https://github.com/fr1j0/claude-light/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/fr1j0/claude-light?include_prereleases&style=for-the-badge&color=34C759"></a>
  <img alt="Made for Claude Code" src="https://img.shields.io/badge/Made_for-Claude_Code-D97757?style=for-the-badge">
</p>

## Overview

Claude Light watches every Claude Code session on your Mac and distills them into a single traffic light in the menu bar. One glance tells you whether an agent is waiting on you, still working, or done — no alt-tabbing through terminals to find out.

## At a Glance

<p align="center">
  <img src="assets/menu-states.svg" alt="Menu-bar icon states: needs you, working, idle, no sessions" width="520">
</p>

The menu-bar icon reflects the most urgent state across all your sessions:

| Lamp | Meaning | Motion |
|------|---------|--------|
| <img src="assets/lamp-red.svg" width="22" alt=""> Top — red | A session needs you: a question, permission prompt, or review request is waiting | Blinks (question) · steady (permission, review) |
| <img src="assets/lamp-orange.svg" width="22" alt=""> Middle — orange | At least one session is actively working | Gentle pulse |
| <img src="assets/lamp-green.svg" width="22" alt=""> Bottom — green | Sessions are idle; nothing needs you | Steady |
| <img src="assets/lamp-dim.svg" width="22" alt=""> All dim | No live sessions | Steady |

Red always wins the aggregate, so a single waiting session is never buried behind busy ones. Motion is reserved for the menu bar — a blink to pull your eye when a session needs a reply, a soft pulse while work is underway — and state is conveyed by lamp position as well as color.

## The Dropdown

Click the icon for the full picture:

- A one-line summary header, such as `1 needs you · 2 working`.
- One card per session, sorted by urgency: status dot, project name, a live
  elapsed-state timer, and — when a session is blocked — the actual question
  or permission request it's waiting on.
- Running sessions with parallel subagents show them as collapsible rows
  inside the card.
- Click a card to jump to that session's terminal.
- Settings flip in place: show subagents, launch at login, needs-you
  notifications, and one-click install or removal of the Claude Code hooks.
- Quit and the running version live in the footer.

## Features

- Native menu-bar app — lightweight, no dock icon, no window.
- Aggregate traffic light across any number of concurrent sessions.
- A distinct, chunky traffic-light icon that adapts to light and dark menu bars.
- Live updates via filesystem events — the display reacts within a fraction of a second.
- Opt-in native notification when a session flips to needs-you — click it to jump to that terminal.
- Launch-at-login toggle, so the light is always on duty.
- No polling, no network, no telemetry.
- Zero configuration beyond a one-click hook install.

## How It Works

Claude Light integrates with Claude Code through a small hook shim. On each Claude Code hook event, the shim writes that session's state to `~/.claude-light/sessions/`. The app watches that folder and updates its display the moment anything changes.

For the full technical design, see the specs under [`docs/superpowers/specs/`](docs/superpowers/specs/).

## Installation

### Homebrew (recommended)

```bash
brew tap fr1j0/claude-light
brew trust fr1j0/claude-light   # newer Homebrew requires trusting third-party taps
brew install --cask claude-light
```

Update any time with `brew upgrade --cask claude-light`. There is no auto-update or in-app update check — updates only arrive through Homebrew (or by downloading a newer release manually).

### From GitHub Releases

Download the latest `.app` from [GitHub Releases](https://github.com/fr1j0/claude-light/releases) and verify the published SHA-256 checksum to confirm authenticity.

> **Note — unsigned interim builds:** releases are currently ad-hoc signed while Apple notarization for the team is pending, so on first launch Gatekeeper may report the app as *"damaged and can't be opened"*. Clear the quarantine flag and launch again:
>
> ```bash
> xattr -dr com.apple.quarantine "/Applications/Claude Light.app"
> ```

## First Run

1. Launch Claude Light — a traffic-light icon appears in the menu bar.
2. Click the icon and choose **Install Claude Code hooks**. This safely merges the hook entries into `~/.claude/settings.json`.
3. Your next Claude Code prompt lights up the menu.
4. **Remove Claude Code hooks** cleanly undoes the change at any time.

## Build from Source

Requires Swift 5.9+ and macOS 13+.

```bash
swift build -c release          # build the app and hook binaries
swift test                      # run the test suite
bash scripts/package-app.sh     # produce dist/Claude Light.app
```

## Security & Trust

Claude Light edits your settings and runs on every Claude Code hook, so it is fully open source and auditable — read the source and verify it for yourself. Current releases are interim builds **without** Developer ID signing or notarization (pending Apple enabling notarization for the team); until that lands, authenticity rests on the published SHA-256 checksums and the auditable source. Once notarization is enabled, official builds will be signed and notarized, removing the Gatekeeper warning and guaranteeing the binary has not been tampered with.

Install only from the official [Releases](https://github.com/fr1j0/claude-light/releases), and verify the published SHA-256 checksum before running.

## License & Trademark

Licensed under [Apache-2.0](LICENSE). The name "Claude Light", logo, and icon are **not** licensed under Apache-2.0 — see [TRADEMARK.md](TRADEMARK.md) for details.

"Claude" is a trademark of Anthropic. This is an independent community project, not affiliated with or endorsed by Anthropic.
