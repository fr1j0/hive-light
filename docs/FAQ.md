# FAQ

### What is Hive Light?

A native macOS menu-bar traffic light for your Claude Code sessions: **red** when a
session needs you, **orange** while the hive hums, **green** when all is quiet. One
glance instead of cycling through terminal tabs. See the [README](../README.md) for
the full feature tour.

### Which terminals does it work with?

iTerm2, Apple Terminal, Warp, and VS Code's integrated terminal. Clicking a session
card jumps to that session's terminal. Warp focuses the exact tab on recent Warp
versions (mid-2026 onward); older Warp versions focus the app window.

### Does Hive Light send my data anywhere?

No. Everything stays on your machine — status files under `~/.hive-light/`, read via
filesystem events. There is one **opt-in** exception: the *Fetch plan limits* setting
asks Anthropic's API (using your existing Claude Code login) for your own plan-limit
numbers so the usage view can show them. Off by default; nothing else ever leaves
your Mac. Details in [PRIVACY.md](../PRIVACY.md).

### Does it read my conversations?

The hook shim receives Claude Code's hook events, and the app reads the tail of a
session's local transcript to show useful detail — the question a session is waiting
on, context usage, the model badge. All of that is read locally and displayed
locally; none of it is transmitted.

### Why does the install need `brew trust`?

Newer Homebrew versions require explicitly trusting third-party taps before
installing from them:

```bash
brew tap fr1j0/hive-light
brew trust fr1j0/hive-light
brew install --cask hive-light
```

### Why does macOS say the app is "damaged and can't be opened"?

Current releases are interim builds without Developer ID notarization (Apple is
still enabling notarization for the team). Clear the quarantine flag and launch
again:

```bash
xattr -dr com.apple.quarantine "/Applications/Hive Light.app"
```

Authenticity meanwhile rests on the published SHA-256 checksums and the auditable
source — see [Security & Trust](../README.md#security--trust). Once notarization
lands, official builds will be signed and notarized and this step disappears.

### How do I update?

`brew upgrade --cask hive-light`. There is no auto-update or in-app update check.

### How do I uninstall cleanly?

1. In the dropdown's settings, choose **Remove Claude Code hooks** (cleanly undoes
   the `~/.claude/settings.json` change).
2. `brew uninstall --cask hive-light`.
3. Optionally delete the state directory: `rm -rf ~/.hive-light`.

### Wasn't this called Claude Light?

Yes — renamed to Hive Light in July 2026. "Claude" is a trademark of Anthropic and
Hive Light is an independent community project, not affiliated with or endorsed by
Anthropic. Upgrades from Claude Light migrate automatically on first launch.

### Why "Hive Light"?

*hive light, n.* — the single glow by which a colony of many independent workers can
be read as one organism; the state of the whole, never of any one bee. Your sessions
are the bees; you are the keeper who steps in only when something truly needs you.

---

Something not answered here? Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or
[open an issue](https://github.com/fr1j0/hive-light/issues).
