# Troubleshooting

### The light never turns on / no sessions appear

1. Install the hooks: click the menu-bar icon → **Install Claude Code hooks**.
2. Hooks only apply to **new** Claude Code sessions — start a fresh session (or send
   a new prompt in a fresh terminal tab) and the light should react.
3. Verify the hook entries exist in `~/.claude/settings.json` (look for
   `hive-light-hook`).
4. Verify state files appear: `ls ~/.hive-light/sessions/` should list one JSON file
   per live session after a prompt.

### The app won't open — "damaged and can't be opened"

Interim releases are not yet notarized. Clear quarantine and relaunch:

```bash
xattr -dr com.apple.quarantine "/Applications/Hive Light.app"
```

See the [FAQ](FAQ.md#why-does-macos-say-the-app-is-damaged-and-cant-be-opened) for
why this happens and when it will stop being necessary.

### The light went dead after upgrading from Claude Light

The rename migration runs automatically on first launch: your `~/.claude-light`
state moves to `~/.hive-light`, settings carry over, and dead hook entries pointing
at the old `Claude Light.app` are rewritten. If a session still doesn't register:

1. Click the icon → **Remove Claude Code hooks**, then **Install Claude Code hooks**.
2. Start a new Claude Code session.

The rename also changed the app's bundle identifier, which resets two macOS-managed
permissions — re-enable **launch at login** and **notifications** if you used them.

### Notifications don't appear

1. Notifications are opt-in: enable the needs-you notification toggle in the
   dropdown's settings.
2. Check macOS System Settings → Notifications → Hive Light is allowed.
3. On unsigned interim builds, macOS can drop the notification permission after an
   update (the binary's identity changes without a stable signature). Re-grant it in
   System Settings; this stops happening once notarized builds ship.

### Clicking a session doesn't focus the right terminal tab

- **iTerm2 / Apple Terminal**: the exact tab is focused.
- **Warp**: exact-tab focus requires a mid-2026 Warp version or newer; older
  versions focus the Warp window.
- **VS Code**: the window is focused.

### A finished or crashed session lingers in the panel

Sessions expire automatically (hours-long TTL, so a laptop sleep doesn't kill your
list). If something is truly stuck, quit Hive Light, delete the stale file from
`~/.hive-light/sessions/`, and relaunch.

### Usage stats don't show

Both are opt-in, in the dropdown's settings:

1. **Show usage in panel** — the compact 5-hour / weekly strip.
2. **Fetch plan limits** (sub-setting) — the plan-limit percentages, fetched with
   your existing Claude Code login. Requires being logged in to Claude Code.

### Where does Hive Light keep its data?

- Session state: `~/.hive-light/`
- Hook entries: `~/.claude/settings.json` (added and removed via the in-app
  install/remove actions)

Deleting both removes every trace — see the uninstall steps in the
[FAQ](FAQ.md#how-do-i-uninstall-cleanly).

---

Still stuck? [Open an issue](https://github.com/fr1j0/hive-light/issues) with your
macOS version, Hive Light version (panel footer), and what
`ls ~/.hive-light/sessions/` shows.
