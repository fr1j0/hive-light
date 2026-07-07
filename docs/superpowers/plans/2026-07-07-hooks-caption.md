# Hooks Card Caption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a caption to the Settings hooks card explaining that hook changes only affect new Claude Code sessions.

**Architecture:** View-only edit inside `hooksCard` in `SettingsPane.swift`: the button label becomes a two-line VStack (existing title row + new caption). The caption lives inside the button so the card stays the one clickable surface with a single hover fill.

**Tech Stack:** SwiftUI (macOS 13+), SwiftPM.

**Spec:** `docs/superpowers/specs/2026-07-07-hooks-caption-design.md`

## Global Constraints

- Caption text exactly: "Changes apply to new Claude Code sessions — ones already running keep their current hooks until they end."
- Caption typography matches the settings caption grammar: 10 pt system font, `.tertiary`, wrapping enabled.
- No behavior changes: install/remove actions, `hooksInstalled`, `hookActionError` untouched.
- Work happens on branch `feat/hooks-caption` (already created, spec committed).

---

### Task 1: Caption inside the hooks card

**Files:**
- Modify: `Sources/HiveLightApp/SettingsPane.swift:188-207` (`private var hooksCard`)

**Interfaces:**
- Consumes: existing `watcher.hooksInstalled`, `hookHover` state, the card background/hover pattern visible in the current code.
- Produces: nothing new outside the file — visual change only.

- [ ] **Step 1: Make the edit**

Replace the `Button`'s label content:

```swift
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "link").font(.system(size: 11))
                Text(watcher.hooksInstalled ? "Remove Claude Code hooks" : "Install Claude Code hooks")
                    .font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
```

with:

```swift
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: "link").font(.system(size: 11))
                    Text(watcher.hooksInstalled ? "Remove Claude Code hooks" : "Install Claude Code hooks")
                        .font(.system(size: 12))
                    Spacer(minLength: 0)
                }
                // Hook config is snapshotted per Claude Code session, so the
                // click's effect is invisible until sessions cycle — say so.
                Text("Changes apply to new Claude Code sessions — ones already running keep their current hooks until they end.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
```

- [ ] **Step 2: Run the full test suite (regression gate — view-only change, no new tests)**

Run: `swift test 2>&1 | grep -E "Test Suite 'All tests' (passed|failed)" | tail -1`
Expected: `Test Suite 'All tests' passed ...`

- [ ] **Step 3: Commit**

```bash
git add Sources/HiveLightApp/SettingsPane.swift
git commit -m "feat: hooks card explains the per-session snapshot delay"
```

---

### Task 2: Live verification (deploy the dev build and eyeball it)

**Files:**
- None modified — build, sign, swap per the established local flow.

**Interfaces:**
- Consumes: Task 1's commit; `scripts/package-app.sh`; identity `Developer ID Application: Fernando Castillo (7MTZYB93KB)`.
- Produces: the running app for the user's visual verdict.

- [ ] **Step 1: Package the app**

Run: `scripts/package-app.sh`
Expected: exits 0; `dist/Hive Light.app` exists.

- [ ] **Step 2: Re-sign (hook binary, app binary, then bundle — this order)**

```bash
IDENTITY="Developer ID Application: Fernando Castillo (7MTZYB93KB)"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "dist/Hive Light.app/Contents/MacOS/hive-light-hook"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "dist/Hive Light.app/Contents/MacOS/HiveLightApp"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "dist/Hive Light.app"
codesign --verify --deep --strict "dist/Hive Light.app"
```

Expected: final verify prints nothing (exit 0).

- [ ] **Step 3: Swap into /Applications and relaunch**

```bash
osascript -e 'quit app "Hive Light"' 2>/dev/null || true
ditto "dist/Hive Light.app" "/Applications/Hive Light.app"
open "/Applications/Hive Light.app"
```

Expected: app relaunches (`pgrep -x HiveLightApp` prints a pid).

- [ ] **Step 4: User visual check (checkpoint — wait for verdict)**

Settings → hooks card: caption renders under the button title without clipping, hover fill covers the taller card, and the caption reads correctly under both titles (toggle install/remove to see both). If the verdict is "discard": `git revert` Task 1's commit and redeploy.
