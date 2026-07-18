# Task Progress Bar + Usage Blues Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 2pt progress bar under the current-task line, and a fixed blue depth ladder for the bottom usage strip's bars (replacing urgency coloring there).

**Architecture:** One pure helper in `HiveLightCore/PanelModel.swift` (TDD), the bar in `SessionCard.swift`'s `TaskBlock`, the palette + recolor in `UsageRow.swift`. View changes verified by build + live deploy.

**Tech Stack:** Swift 5 / SwiftUI, SwiftPM, XCTest.

## Global Constraints

- **Pre-flight:** if PRs #183/#184 have merged by execution time, rebase this branch onto fresh main first (`git fetch && git rebase origin/main`) — conflicts are append-only in `PanelModel.swift` and additive in `TaskBlock`; resolve by keeping both sides.
- Bar: 2pt tall, cornerRadius 1, leading inset 12pt, track `Color.primary.opacity(0.12)`, fill `PanelPalette.orange.opacity(0.75)`, width fraction `taskProgressFraction(summary)`. NO percent label.
- Blues, by row index in the displayed limits: 0 → `#8FB7D9`, 1 → `#5A96D6`, ≥2 → `#2F6FC4`. Bars never change hue with utilization.
- `UsagePalette.urgency(_:)` is NOT deleted — `UsageView` still uses it.
- The `· done/total tasks` text, labels, `%` text, and countdowns are untouched.
- No AI attribution in commit messages.

---

### Task 1: taskProgressFraction (TDD) + the bar in TaskBlock

**Files:**
- Modify: `Sources/HiveLightCore/PanelModel.swift` (append after `taskHistoryToggleText`)
- Modify: `Sources/HiveLightApp/SessionCard.swift` (`TaskBlock` body)
- Test: `Tests/HiveLightCoreTests/PanelModelTests.swift`

**Interfaces:**
- Consumes: `TaskSummary` (`doneCount: Int`, `total: Int`).
- Produces: `public func taskProgressFraction(_ summary: TaskSummary) -> Double` (0...1, 0 when total == 0).

- [ ] **Step 1: Write the failing test**

Add to `PanelModelTests.swift` after `test_taskHistoryToggleText_countFreeLabel`:

```swift
    func test_taskProgressFraction_clampedRatio() {
        XCTAssertEqual(taskProgressFraction(TaskSummary(
            inProgressSubject: "n", total: 8,
            doneSubjects: ["1", "2", "3", "4"])), 0.5)
        XCTAssertEqual(taskProgressFraction(TaskSummary(
            inProgressSubject: "n", total: 3, doneSubjects: [])), 0)
        XCTAssertEqual(taskProgressFraction(TaskSummary(
            inProgressSubject: "n", total: 0, doneSubjects: [])), 0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PanelModelTests 2>&1 | grep -E "error:|Executed" | head -3`
Expected: build FAILURE, `cannot find 'taskProgressFraction' in scope`

- [ ] **Step 3: Implement the helper**

In `Sources/HiveLightCore/PanelModel.swift`, append after `taskHistoryToggleText`:

```swift
/// Fill fraction for the task progress bar under the current-task row —
/// done over total, clamped to 0...1 (0 when the list is empty).
public func taskProgressFraction(_ summary: TaskSummary) -> Double {
    guard summary.total > 0 else { return 0 }
    return min(max(Double(summary.doneCount) / Double(summary.total), 0), 1)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PanelModelTests 2>&1 | grep -E "Executed" | tail -1`
Expected: PASS, 0 failures.

- [ ] **Step 5: Add the bar to TaskBlock**

In `Sources/HiveLightApp/SessionCard.swift`, inside `TaskBlock`'s outer `VStack`, insert immediately AFTER the closing brace of the current-task `HStack(spacing: 5)` (the one holding the ■ `Rectangle` and the `inProgressSubject` text — anchor on that content, not line numbers):

```swift
            // Progress echo of the "· done/total" count — shape channel only,
            // no number (the text already says it once).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(PanelPalette.orange.opacity(0.75))
                        .frame(width: geo.size.width * taskProgressFraction(summary))
                }
            }
            // Greedy width: a GeometryReader's ideal width is ~10pt and this
            // panel sizes to ideals — without maxWidth the bar collapses.
            .frame(maxWidth: .infinity)
            .frame(height: 2)
            .padding(.leading, 12)
```

- [ ] **Step 6: Full suite + commit**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: all tests pass (baseline count + 1).

```bash
git add Sources/HiveLightCore/PanelModel.swift Sources/HiveLightApp/SessionCard.swift Tests/HiveLightCoreTests/PanelModelTests.swift
git commit -m "feat: progress bar under the current-task line"
```

---

### Task 2: Blue depth ladder for the usage strip

**Files:**
- Modify: `Sources/HiveLightApp/UsageRow.swift` (`UsagePalette`, `body`, `limitLine`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `static func bucketBlue(rowIndex: Int) -> Color` on `UsagePalette`.

- [ ] **Step 1: Add the palette ladder**

In `UsageRow.swift`, inside `enum UsagePalette`, add after the `urgency` function:

```swift
    /// The bottom strip's capacity bars: a fixed blue depth ladder by row —
    /// calm identity per bucket, never urgency ("blue always", 2026-07-18
    /// spec). The % text and countdown carry the alarm. UsageView still
    /// speaks urgency; this ladder is the strip's voice only.
    static func bucketBlue(rowIndex: Int) -> Color {
        switch rowIndex {
        case 0: return Color(red: 0.561, green: 0.718, blue: 0.851)  // #8FB7D9
        case 1: return Color(red: 0.353, green: 0.588, blue: 0.839)  // #5A96D6
        default: return Color(red: 0.184, green: 0.435, blue: 0.769) // #2F6FC4
        }
    }
```

- [ ] **Step 2: Thread the row index into limitLine**

In `UsageRow.body`, replace:

```swift
                        ForEach(limits, id: \.label) { limitLine($0) }
```

with:

```swift
                        ForEach(Array(limits.enumerated()), id: \.element.label) {
                            limitLine($1, rowIndex: $0)
                        }
```

Change `limitLine`'s signature from:

```swift
    private func limitLine(_ limit: PlanLimit) -> some View {
```

to:

```swift
    private func limitLine(_ limit: PlanLimit, rowIndex: Int) -> some View {
```

and inside it replace the fill:

```swift
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(UsagePalette.urgency(limitLevel(limit)))
```

with:

```swift
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(UsagePalette.bucketBlue(rowIndex: rowIndex))
```

If `limitLevel(_:)` is now unreferenced in this file, delete it — but first `grep -rn "limitLevel" Sources Tests`; keep it if anything else uses it.

- [ ] **Step 3: Full suite + commit**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: all tests pass, same count as after Task 1.

```bash
git add Sources/HiveLightApp/UsageRow.swift
git commit -m "feat: usage strip bars wear a fixed blue depth ladder"
```

---

### Task 3: Live verify + deploy + PR (controller-run)

- [ ] Build Release (`scripts/package-app.sh`), sign with the local Developer ID, swap into /Applications, relaunch. If #183/#184 are still unmerged, build a temporary local integration merge for the deploy only — the PR branch stays clean.
- [ ] User verdict at the panel: bar fills 4/8 under the demo card's task line, no % label; strip rows light→mid→deep blue top to bottom; % + countdowns unchanged.
- [ ] On "all good": push branch, open PR to main.
