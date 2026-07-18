# Task History Single Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold all completed tasks under one count-free `earlier tasks` disclosure (collapsed by default), removing the "+N earlier" count and the always-visible last-2 struck rows.

**Architecture:** Pure-function label builder lives in `HiveLightCore/PanelModel.swift` (unit-tested); the SwiftUI rendering lives in `HiveLightApp/SessionCard.swift` (`TaskBlock`). Task 1 adds the new label function alongside the old one so every task compiles green; Task 2 switches the view to it and deletes the old function, its constant, and its test.

**Tech Stack:** Swift 5 / SwiftUI, SwiftPM, XCTest.

## Global Constraints

- Toggle label is exactly `"earlier tasks"` in both states — never a count.
- Toggle renders only when ≥1 task is completed.
- Visual treatment unchanged: chevron 8pt bold, label 10.5pt tertiary, struck 11pt rows with dimmed green checkmarks, `easeOut(duration: 0.12)` animation, `maxInlineRows = 8`, `scrollBlockHeight = 128`.
- The `· done/total tasks` suffix on the current-task line stays as-is.
- No AI attribution in commit messages (repo convention).

---

### Task 1: Count-free label builder in PanelModel

**Files:**
- Modify: `Sources/HiveLightCore/PanelModel.swift:82-90`
- Test: `Tests/HiveLightCoreTests/PanelModelTests.swift:101-108`

**Interfaces:**
- Consumes: `TaskSummary` (existing: `inProgressSubject: String`, `total: Int`, `doneSubjects: [String]`).
- Produces: `public func taskHistoryToggleText(_ summary: TaskSummary) -> String?` — returns `"earlier tasks"` when `summary.doneSubjects` is non-empty, else `nil`. Task 2 calls this from `TaskBlock`. The old `taskHistoryOverflowText` and `taskHistoryVisibleCount` remain until Task 2 deletes them.

- [ ] **Step 1: Write the failing test**

Add to `Tests/HiveLightCoreTests/PanelModelTests.swift`, directly after `test_taskHistoryOverflowText_countsBeyondVisible` (line 108):

```swift
    func test_taskHistoryToggleText_countFreeLabel() {
        let many = TaskSummary(inProgressSubject: "Now", total: 8,
                               doneSubjects: ["1", "2", "3", "4", "5", "A", "B"])
        XCTAssertEqual(taskHistoryToggleText(many), "earlier tasks")
        let one = TaskSummary(inProgressSubject: "Now", total: 2,
                              doneSubjects: ["A"])
        XCTAssertEqual(taskHistoryToggleText(one), "earlier tasks")
        let none = TaskSummary(inProgressSubject: "Now", total: 1,
                               doneSubjects: [])
        XCTAssertNil(taskHistoryToggleText(none))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PanelModelTests 2>&1 | tail -5`
Expected: build FAILURE with `cannot find 'taskHistoryToggleText' in scope`

- [ ] **Step 3: Write minimal implementation**

In `Sources/HiveLightCore/PanelModel.swift`, add after the `taskHistoryOverflowText` function (after line 87):

```swift
/// The count-free disclosure label hiding the full completed-task history,
/// or nil when nothing has finished yet.
public func taskHistoryToggleText(_ summary: TaskSummary) -> String? {
    summary.doneSubjects.isEmpty ? nil : "earlier tasks"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PanelModelTests 2>&1 | tail -5`
Expected: all PanelModelTests PASS (including the old overflow test — it still exists in this task).

- [ ] **Step 5: Commit**

```bash
git add Sources/HiveLightCore/PanelModel.swift Tests/HiveLightCoreTests/PanelModelTests.swift
git commit -m "feat: count-free earlier-tasks toggle label"
```

---

### Task 2: TaskBlock renders one disclosure over the full history

**Files:**
- Modify: `Sources/HiveLightApp/SessionCard.swift:155-192` (`TaskBlock`)
- Modify: `Sources/HiveLightCore/PanelModel.swift:82-90` (delete old API)
- Modify: `Sources/HiveLightCore/TaskSummaryDetection.swift:4` (doc comment)
- Test: `Tests/HiveLightCoreTests/PanelModelTests.swift:101-108` (delete old test)

**Interfaces:**
- Consumes: `taskHistoryToggleText(_:)` from Task 1.
- Produces: nothing new — deletes `taskHistoryOverflowText(_:)`, `taskHistoryVisibleCount`, and `test_taskHistoryOverflowText_countsBeyondVisible`. No other call sites exist (verified by grep; only `SessionCard.swift` and the one test reference them).

- [ ] **Step 1: Rewrite the TaskBlock disclosure**

In `Sources/HiveLightApp/SessionCard.swift`, replace the header comment (lines 155-158) with:

```swift
/// The owning-task block: an optional count-free "earlier tasks" disclosure
/// that hides the full completed history (struck rows, chronological, long
/// histories scroll internally), then the current task at full text strength
/// behind the terminal's ■ marker.
```

Replace the body's disclosure section — everything from `if let overflow = taskHistoryOverflowText(summary) {` (line 165) through the standalone `historyRows(...)` call at line 192 — with:

```swift
            if let toggle = taskHistoryToggleText(summary) {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { historyExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: historyExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(toggle)
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)

                if historyExpanded {
                    // Chronological unfold of the full history. Long
                    // histories scroll internally, same cap as the fan-out
                    // block.
                    if summary.doneSubjects.count > Self.maxInlineRows {
                        ScrollView { historyRows(summary.doneSubjects) }
                            .frame(height: Self.scrollBlockHeight)
                    } else {
                        historyRows(summary.doneSubjects)
                    }
                }
            }
```

(The `HStack` with the ■ marker and current-task line that followed line 192 stays untouched. `historyRows`, `maxInlineRows`, and `scrollBlockHeight` stay untouched.)

- [ ] **Step 2: Delete the old API**

In `Sources/HiveLightCore/PanelModel.swift`, delete the `taskHistoryOverflowText` function with its doc comment (lines 82-87) and the `taskHistoryVisibleCount` constant with its doc comment (lines 89-90).

In `Sources/HiveLightCore/TaskSummaryDetection.swift` line 4, change:

```swift
/// history (struck rows + expandable "+N earlier" disclosure), and the total.
```

to:

```swift
/// history (struck rows under an "earlier tasks" disclosure), and the total.
```

- [ ] **Step 3: Delete the old test**

In `Tests/HiveLightCoreTests/PanelModelTests.swift`, delete `test_taskHistoryOverflowText_countsBeyondVisible` (lines 101-108).

- [ ] **Step 4: Run the full suite to verify everything compiles and passes**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed` — same total as before minus one deleted test, plus the Task 1 test.

- [ ] **Step 5: Commit**

```bash
git add Sources/HiveLightApp/SessionCard.swift Sources/HiveLightCore/PanelModel.swift Sources/HiveLightCore/TaskSummaryDetection.swift Tests/HiveLightCoreTests/PanelModelTests.swift
git commit -m "feat: fold all completed tasks under a single earlier-tasks toggle"
```

---

### Task 3: README reflects the single toggle

**Files:**
- Modify: `README.md:65-68`

**Interfaces:**
- Consumes: nothing (docs only).
- Produces: nothing.

- [ ] **Step 1: Update the session-activity bullet**

In `README.md`, replace lines 65-68:

```markdown
- Running task-driven sessions show what they're on: the current tracker task
  with progress (`Task 6: docs + quality gate · 5/7 tasks`), recently
  completed tasks struck through, and a `+N earlier` disclosure that unfolds
  the full history.
```

with:

```markdown
- Running task-driven sessions show what they're on: the current tracker task
  with progress (`Task 6: docs + quality gate · 5/7 tasks`), plus an
  `earlier tasks` disclosure that unfolds the completed history, struck
  through.
```

- [ ] **Step 2: Verify nothing else references the old grammar**

Run: `grep -rn "+N earlier\|taskHistoryOverflowText\|taskHistoryVisibleCount" README.md Sources Tests`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README reflects single earlier-tasks toggle"
```
