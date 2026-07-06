# Footer Cell Bullet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hollow hive-cell glyph (SF Symbol `hexagon`) before the "Hive Light v\<version\>" wordmark in the dropdown panel's footer.

**Architecture:** Pure view chrome in one file — the footer's version `Text` in `PanelContent.swift` becomes an `HStack` of a 9 pt `hexagon` symbol plus the existing 11 pt text, both in the existing `.tertiary` style. No model, logic, or test-target changes.

**Tech Stack:** SwiftUI (macOS 13+), SF Symbols, SwiftPM.

**Spec:** `docs/superpowers/specs/2026-07-06-footer-cell-bullet-design.md`

## Global Constraints

- Glyph is SF Symbol `hexagon` (hollow, pointy-top) at 9 pt — no custom `Shape`.
- Color is `.tertiary`, applied to glyph and text together — no new color role.
- 5 pt spacing between glyph and text; default center-aligned `HStack`
  (revised from `.firstTextBaseline` after the live check — baseline
  alignment seated the lockup visibly low in the footer row).
- Glyph is decorative: `.accessibilityHidden(true)`.
- Footer only — no other panel surface gains the motif.
- Work happens on branch `feat/footer-cell-bullet` (already created, spec committed).

---

### Task 1: Footer wordmark HStack

**Files:**
- Modify: `Sources/HiveLightApp/PanelContent.swift:187-189` (the `if let version` block inside `footer`)

**Interfaces:**
- Consumes: `Self.appVersion` (existing `String?`), `footer` layout (existing `HStack(spacing: 8)`).
- Produces: nothing new — visual change only.

- [ ] **Step 1: Make the edit**

Replace this block inside `private var footer`:

```swift
if let version = Self.appVersion {
    Text("Hive Light v\(version)").font(.system(size: 11)).foregroundStyle(.tertiary)
}
```

with:

```swift
if let version = Self.appVersion {
    // The panel's one brand touch (see 2026-07-06 spec): a hollow hive
    // cell folded into the wordmark — same tertiary as the text, so it
    // reads as part of the name, never as a status signal.
    HStack(spacing: 5) {
        Image(systemName: "hexagon")
            .font(.system(size: 9))
            .accessibilityHidden(true)
        Text("Hive Light v\(version)").font(.system(size: 11))
    }
    .foregroundStyle(.tertiary)
}
```

- [ ] **Step 2: Run the full test suite (regression gate — no new tests; this is view chrome outside the XCTest suite's reach by design)**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed` — same count as before the edit (333+), zero failures.

- [ ] **Step 3: Commit**

```bash
git add Sources/HiveLightApp/PanelContent.swift
git commit -m "feat: hive-cell bullet before the footer wordmark"
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

Expected: app relaunches; menu-bar lamp reappears.

- [ ] **Step 4: User visual check (checkpoint — wait for verdict)**

Open the panel and confirm, in BOTH appearances (System Settings → Appearance, or leave to the user's current theme plus one manual flip):
- hollow hexagon sits 5 pt before "Hive Light v0.21.0", same grey as the text;
- glyph is optically centered on the text's cap height (not floating high/low);
- footer's leading/trailing alignment is undisturbed (gear still optically aligns with the header dot).

If the verdict is "discard": revert the Task 1 commit cleanly (`git revert`), redeploy the previous build, and do NOT treat the discard as failure — the live build is a design probe.
