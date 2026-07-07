# Usage Settings Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Settings Usage card express the real dependency — "Show plan limits" is a data source of the usage row, not an independent feature — by relabeling both toggles and dimming/disabling the limits sub-setting while the master is off.

**Architecture:** View-only change to the Usage card in `SettingsPane.swift`: two relabels, an extended disabled/dim condition, and a three-state caption extracted into a computed property. No model, persistence, or panel-logic changes.

**Tech Stack:** SwiftUI (macOS 13+), SwiftPM.

**Spec:** `docs/superpowers/specs/2026-07-07-usage-settings-hierarchy-design.md`

## Global Constraints

- Master relabels to exactly "Show usage in panel"; sub-setting to exactly "Fetch plan limits from Anthropic"; `MiniSwitch` accessibility `label:` arguments match the visible labels.
- Sub-setting disabled/dim condition is exactly `!hasOAuthLogin || !watcher.showUsageStats`, rendered with the existing grammar: `.disabled(...)` on the switch, `0.4` opacity on the row — no new indentation or chrome.
- Caption priority: no-OAuth text wins over master-off text; enabled text last. Exact strings in Task 1.
- Defaults keys and semantics unchanged (`showUsageStats`, `showPlanLimits`); `usageRowVisible` in `PanelContent.swift` untouched; no migration.
- Work happens on branch `feat/usage-settings-hierarchy` (already created, spec committed).

---

### Task 1: Usage card relabels + dependency dimming

**Files:**
- Modify: `Sources/HiveLightApp/SettingsPane.swift:43-58` (the Usage `sectionTitle` + `card` block) and add one computed property near `hasOAuthLogin` (declared at `SettingsPane.swift:14`)

**Interfaces:**
- Consumes: existing helpers `row(_:control:)`, `caption(_:)`, `insetDivider`, `card(_:)`, `MiniSwitch(isOn:label:)`, `hasOAuthLogin`, `watcher.showUsageStats` / `watcher.showPlanLimits` (both published Bools).
- Produces: nothing new outside the file — visual change only.

- [ ] **Step 1: Add the caption helper property**

Directly below the `hasOAuthLogin` declaration (`private let hasOAuthLogin = LimitsFetcher.oauthLoginPresent()`), add:

```swift
    /// Three-state hint for the plan-limits sub-setting. The missing login
    /// outranks the master toggle: no login means the switch can never work,
    /// while master-off is fixable one row above.
    private var planLimitsCaption: String {
        if !hasOAuthLogin {
            return "Requires a Claude subscription login in Claude Code — API-key and Bedrock/Vertex setups have no plan limits."
        }
        if !watcher.showUsageStats {
            return "Plan limits appear in the usage row — turn on Show usage in panel first."
        }
        return "Reads your Claude Code login from the Keychain to fetch limits from Anthropic. Nothing else is sent."
    }
```

- [ ] **Step 2: Rewrite the Usage card block**

Replace this block:

```swift
            sectionTitle("Usage")
            card {
                row("Show usage stats") {
                    MiniSwitch(isOn: $watcher.showUsageStats, label: "Show usage stats")
                }
                caption("Usage row in the panel · click it for details")
                insetDivider
                row("Show plan limits") {
                    MiniSwitch(isOn: $watcher.showPlanLimits, label: "Show plan limits")
                        .disabled(!hasOAuthLogin)
                }
                .opacity(hasOAuthLogin ? 1 : 0.4)
                caption(hasOAuthLogin
                        ? "Reads your Claude Code login from the Keychain to fetch limits from Anthropic. Nothing else is sent."
                        : "Requires a Claude subscription login in Claude Code — API-key and Bedrock/Vertex setups have no plan limits.")
            }
```

with:

```swift
            sectionTitle("Usage")
            card {
                row("Show usage in panel") {
                    MiniSwitch(isOn: $watcher.showUsageStats, label: "Show usage in panel")
                }
                caption("Usage row in the panel · click it for details")
                insetDivider
                // Plan limits are a data source of the usage row, not a
                // separate display — the row must exist for them to show.
                row("Fetch plan limits from Anthropic") {
                    MiniSwitch(isOn: $watcher.showPlanLimits, label: "Fetch plan limits from Anthropic")
                        .disabled(!hasOAuthLogin || !watcher.showUsageStats)
                }
                .opacity(hasOAuthLogin && watcher.showUsageStats ? 1 : 0.4)
                caption(planLimitsCaption)
            }
```

- [ ] **Step 3: Run the full test suite (regression gate — view-only change, no new tests)**

Run: `swift test 2>&1 | grep -E "Test Suite 'All tests' (passed|failed)" | tail -1`
Expected: `Test Suite 'All tests' passed ...` — zero failures.

- [ ] **Step 4: Commit**

```bash
git add Sources/HiveLightApp/SettingsPane.swift
git commit -m "fix: plan-limits toggle dims while the usage row is off"
```

---

### Task 2: Live verification (deploy the dev build and eyeball it)

**Files:**
- None modified — build, sign, and swap `/Applications/Hive Light.app` per the established local flow.

**Interfaces:**
- Consumes: Task 1's committed edit; `scripts/package-app.sh`; Developer ID identity `Developer ID Application: Fernando Castillo (7MTZYB93KB)`.
- Produces: the running app for the user's visual verdict (final approval is theirs — a discard is a valid outcome).

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

Open the panel → Settings and confirm all three sub-setting states:
- master OFF: "Fetch plan limits from Anthropic" is dimmed + disabled, caption reads "Plan limits appear in the usage row — turn on Show usage in panel first.";
- flip master ON (without closing Settings): sub-toggle re-enables live, caption switches to the Keychain privacy line;
- both ON: usage row renders in the panel as before (predicate untouched).
- (If testable on this machine's login state: the no-OAuth caption still wins over the master-off caption.)

If the verdict is "discard": `git revert` Task 1's commit and redeploy per Steps 1-3.
