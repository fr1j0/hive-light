# Model Chip Top Row Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the model chip from the conditional subtitle row to the title row's trailing stack so it is always visible when the model is known.

**Architecture:** Pure view-layer move inside `SessionCard.swift` — the chip block relocates from the subtitle `HStack` into the gauge/timer `HStack`. No core logic, no new API.

**Tech Stack:** Swift 5 / SwiftUI, SwiftPM, XCTest.

## Global Constraints

- Chip visual treatment unchanged: 9pt semibold, `kerning(0.5)`, tertiary, `.padding(.horizontal, 5)`/`.padding(.vertical, 1)`, `RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.09))`, `.help(model)`, `.layoutPriority(1)`.
- Chip position: inside the trailing `HStack(spacing: 5)`, BEFORE `ContextTicks`.
- Subtitle row: chip and its `Spacer(minLength: 6)` removed; nothing else changes.
- No AI attribution in commit messages.

---

### Task 1: Move the chip to the title row

**Files:**
- Modify: `Sources/HiveLightApp/SessionCard.swift` (title-row HStack ~lines 70-86, subtitle HStack ~lines 88-116)

**Interfaces:**
- Consumes: `session.model: String?`, `shortModelName(_:)` (existing, unchanged).
- Produces: nothing new — layout-only move.

- [ ] **Step 1: Add the chip to the trailing sub-stack**

In `Sources/HiveLightApp/SessionCard.swift`, inside the `HStack(spacing: 5)` that holds `ContextTicks` and the timer, insert BEFORE the `if let fraction = session.contextFraction {` line:

```swift
                    if let model = session.model {
                        // Model chip (#105): one fixed home on the title row —
                        // visible in every mode/state, unlike the old subtitle
                        // slot that vanished with the row (grouped+running).
                        Text(shortModelName(model).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.09)))
                            .layoutPriority(1)
                            .help(model)
                    }
```

- [ ] **Step 2: Remove the chip from the subtitle row**

In the subtitle `HStack(spacing: 8)`, delete the entire block:

```swift
                    if let model = session.model {
                        Spacer(minLength: 6)
                        // Model chip (#105): trailing edge, never compresses —
                        // the subtitle text truncates instead.
                        Text(shortModelName(model).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.09)))
                            .layoutPriority(1)
                            .help(model)
                    }
```

(Keep everything else in the subtitle row exactly as-is.)

- [ ] **Step 3: Run the full suite**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Executed 397 tests, with 0 failures`

- [ ] **Step 4: Commit**

```bash
git add Sources/HiveLightApp/SessionCard.swift
git commit -m "fix: model chip moves to the title row so it survives subtitle suppression"
```

---

### Task 2: Live verify + deploy (controller-run)

- [ ] Build Release, sign with the local Developer ID identity, swap into /Applications, relaunch.
- [ ] User verdict at the panel: chip visible on every session card (grouped mode, running state), FABLE-5 on current sessions; title truncates before chip on narrow titles.
- [ ] On "all good": push branch, open PR.
