# Subagent Progress & Record Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a parallel fan-out's progress (`X of N done`) and keep a struck-through record of completed subagents, scoped to the current since-last-prompt batch.

**Architecture:** All logic lives in the pure `subagents(fromTranscript:)` scanner in `ClaudeLightCore` (state model, batch scoping, counts, row cap) plus its chip-text helper; the SwiftUI `SubagentRows` view renders the new states and counts. No `SessionWatcher` change — subagents stay scanned for running sessions only, so the record's visible lifetime is turn-end (see spec).

**Tech Stack:** Swift 5.9 / SwiftUI, XCTest, Swift Package Manager (`swift test`).

## Global Constraints

- Subagent detection is a pure function over transcript JSONL; unparseable lines are skipped, never crash.
- Labels truncate to 40 chars (existing behavior — preserve).
- Panel palette values are fixed: `red #ff3b30`, `orange #ff9400`; use `PanelPalette` constants, never re-hardcode.
- Row cap is 6 total visible rows; failed are never dropped even past the cap; priority for the budget is failed → running → done.
- `total` = every dispatched agent in the batch; `doneCount` / `failedCount` are exact regardless of the row cap.
- Motion respects `prefers-reduced-motion` (the running pulse dot falls back to static).
- No AI attribution in commits.

---

### Task 1: Extend the detection model — `.done` state, batch scoping, counts, row cap

**Files:**
- Modify: `Sources/ClaudeLightCore/SubagentDetection.swift`
- Test: `Tests/ClaudeLightCoreTests/SubagentDetectionTests.swift`

**Interfaces:**
- Consumes: transcript JSONL string (unchanged input).
- Produces:
  - `enum Subagent.State { case running, done, failed }`
  - `struct SubagentList { let visible: [Subagent]; let total: Int; let doneCount: Int; let failedCount: Int; let overflowRunning: Int; let overflowDone: Int }` with `static let empty` and `var isEmpty: Bool`.
  - `func subagents(fromTranscript jsonl: String, maxRows: Int = 6) -> SubagentList` (parameter renamed from `maxActive`).

- [ ] **Step 1: Write the failing tests**

Replace the two now-obsolete done-hiding tests and add the new behavior. In `Tests/ClaudeLightCoreTests/SubagentDetectionTests.swift`:

Delete `test_toolResultIsErrorFalse_isDone_andHidden` and replace `test_mix_showsRunningAndFailed_hidesDone_preservesOrder`. Then the file's behavior tests become:

```swift
func test_doneSubagent_isShownStruck_notDropped() {
    let t = join([toolUse("t1", "done work"), toolResult("t1", isError: false)])
    let list = subagents(fromTranscript: t)
    XCTAssertEqual(list.visible, [Subagent(id: "t1", label: "done work", state: .done)])
    XCTAssertEqual(list.total, 1)
    XCTAssertEqual(list.doneCount, 1)
}

func test_mix_showsAllThreeStates_inDispatchOrder() {
    let t = join([
        toolUse("a", "Review Task 4"),
        toolUse("b", "Final review"), toolResult("b", isError: false),   // done
        toolUse("c", "Implement Task 5"), toolResult("c", isError: true), // failed
    ])
    let list = subagents(fromTranscript: t)
    XCTAssertEqual(list.visible, [
        Subagent(id: "a", label: "Review Task 4", state: .running),
        Subagent(id: "b", label: "Final review", state: .done),
        Subagent(id: "c", label: "Implement Task 5", state: .failed),
    ])
    XCTAssertEqual(list.total, 3)
    XCTAssertEqual(list.doneCount, 1)
    XCTAssertEqual(list.failedCount, 1)
}

func test_doneSubagent_supersededByLaterUserPrompt_isCleared() {
    let t = join([toolUse("t1", "old batch"), toolResult("t1", isError: false),
                  userPrompt("continue")])
    let list = subagents(fromTranscript: t)
    XCTAssertTrue(list.isEmpty)
    XCTAssertEqual(list.total, 0)
}

func test_denominator_resetsToNewBatchAfterPrompt() {
    // Old batch of 2 (both done) settled before the prompt; new batch of 3
    // dispatched after → count reflects only the new batch.
    let t = join([
        toolUse("o1", "old 1"), toolResult("o1", isError: false),
        toolUse("o2", "old 2"), toolResult("o2", isError: false),
        userPrompt("next"),
        toolUse("n1", "new 1"), toolResult("n1", isError: false),
        toolUse("n2", "new 2"),
        toolUse("n3", "new 3"),
    ])
    let list = subagents(fromTranscript: t)
    XCTAssertEqual(list.total, 3)
    XCTAssertEqual(list.doneCount, 1)
    XCTAssertEqual(list.visible.map(\.id), ["n1", "n2", "n3"])
}

func test_rowCap_keepsFailedAndRunning_collapsesDoneTail() {
    // 1 failed + 2 running + 7 done, cap 6 → 1+2+3 = 6 rows, +4 done overflow.
    var lines = [toolUse("f", "fail"), toolResult("f", isError: true),
                 toolUse("r1", "run 1"), toolUse("r2", "run 2")]
    for i in 1...7 { lines += [toolUse("d\(i)", "done \(i)"), toolResult("d\(i)", isError: false)] }
    let list = subagents(fromTranscript: join(lines), maxRows: 6)
    XCTAssertEqual(list.visible.count, 6)
    XCTAssertEqual(list.overflowDone, 4)
    XCTAssertEqual(list.overflowRunning, 0)
    XCTAssertEqual(list.total, 10)
    XCTAssertEqual(list.doneCount, 7)
    XCTAssertEqual(list.failedCount, 1)
    // Failed + both running always survive the cap.
    XCTAssertEqual(list.visible.filter { $0.state == .failed }.count, 1)
    XCTAssertEqual(list.visible.filter { $0.state == .running }.count, 2)
    XCTAssertEqual(list.visible.filter { $0.state == .done }.count, 3)
}
```

Update the existing running-cap and failed-not-capped tests for the renamed parameter and new fields:

```swift
func test_runningCap_capsAtMaxRows_withOverflowCount() {
    let lines = (1...8).map { toolUse("r\($0)", "subagent \($0)") }
    let list = subagents(fromTranscript: join(lines), maxRows: 5)
    XCTAssertEqual(list.visible.count, 5)
    XCTAssertEqual(list.overflowRunning, 3)
    XCTAssertEqual(list.visible.map(\.id), ["r1", "r2", "r3", "r4", "r5"])
    XCTAssertEqual(list.total, 8)
}

func test_failedNotCapped_alwaysShown() {
    // 6 failed with cap 5 → all failed still visible (never dropped), no overflow.
    let lines = (1...6).flatMap { [toolUse("f\($0)", "f\($0)"), toolResult("f\($0)", isError: true)] }
    let list = subagents(fromTranscript: join(lines), maxRows: 5)
    XCTAssertEqual(list.visible.count, 6)
    XCTAssertEqual(list.failedCount, 6)
    XCTAssertEqual(list.overflowRunning, 0)
    XCTAssertEqual(list.overflowDone, 0)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SubagentDetectionTests`
Expected: FAIL — `.done` not a member of `State`; `total`/`doneCount`/`failedCount`/`overflowDone` not members of `SubagentList`; `maxRows:` label unknown.

- [ ] **Step 3: Implement the model changes**

In `Sources/ClaudeLightCore/SubagentDetection.swift`, replace the `State` enum, the `SubagentList` struct, and the `subagents(...)` function body:

```swift
public struct Subagent: Equatable, Sendable {
    public enum State: String, Sendable { case running, done, failed }
    public let id: String
    public let label: String
    public let state: State

    public init(id: String, label: String, state: State) {
        self.id = id
        self.label = label
        self.state = state
    }
}

/// The subagents to display for a session's current fan-out: capped display
/// rows plus exact batch counts and the per-kind overflow hidden by the cap.
public struct SubagentList: Equatable, Sendable {
    public let visible: [Subagent]
    public let total: Int          // N — every dispatched agent in the batch
    public let doneCount: Int      // X in "X of N done" — exact, cap-independent
    public let failedCount: Int    // exact, cap-independent
    public let overflowRunning: Int
    public let overflowDone: Int

    public init(visible: [Subagent], total: Int, doneCount: Int,
                failedCount: Int, overflowRunning: Int, overflowDone: Int) {
        self.visible = visible
        self.total = total
        self.doneCount = doneCount
        self.failedCount = failedCount
        self.overflowRunning = overflowRunning
        self.overflowDone = overflowDone
    }

    public static let empty = SubagentList(visible: [], total: 0, doneCount: 0,
                                           failedCount: 0, overflowRunning: 0, overflowDone: 0)
    public var isEmpty: Bool {
        visible.isEmpty && overflowRunning == 0 && overflowDone == 0
    }
}
```

Rewrite `subagents(...)`. The batch-scoping change: on a real user prompt, clear every *settled* agent (any id with a `tool_result`, i.e. done **or** failed), keeping running ones. The row cap: failed always shown; running fill the budget; done fill what's left.

```swift
public func subagents(fromTranscript jsonl: String, maxRows: Int = 6) -> SubagentList {
    struct Pending { let id: String; let label: String }
    var order: [Pending] = []
    var seen = Set<String>()
    var errored: [String: Bool] = [:]   // tool_use_id → is_error present (i.e. settled)

    for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any]
        else { continue }

        // A new typed prompt supersedes settled (done + failed) fan-outs so the
        // count re-bases on the current batch; running ones stay (a queued
        // message can land while work is still in flight).
        if isRealUserPrompt(obj: obj, message: message) {
            let settledIDs = Set(errored.keys)
            if !settledIDs.isEmpty {
                order.removeAll { settledIDs.contains($0.id) }
                settledIDs.forEach { errored.removeValue(forKey: $0) }
            }
        }

        guard let content = message["content"] as? [[String: Any]] else { continue }

        for block in content {
            switch block["type"] as? String {
            case "tool_use":
                guard let name = block["name"] as? String, name == "Task" || name == "Agent",
                      let id = block["id"] as? String, !seen.contains(id) else { continue }
                let desc = (block["input"] as? [String: Any])?["description"] as? String ?? ""
                seen.insert(id)
                order.append(Pending(id: id, label: String(desc.prefix(40))))
            case "tool_result":
                guard let id = block["tool_use_id"] as? String else { continue }
                errored[id] = (block["is_error"] as? Bool) ?? false
            default:
                continue
            }
        }
    }

    // Classify in dispatch order.
    func state(of p: Pending) -> Subagent.State {
        guard let isError = errored[p.id] else { return .running }
        return isError ? .failed : .done
    }
    let total = order.count
    let doneCount = order.filter { state(of: $0) == .done }.count
    let failedCount = order.filter { state(of: $0) == .failed }.count

    // Row-cap budget: failed always shown (never dropped, even past the cap);
    // running fill the remaining budget; done fill what's left. Counts are
    // decided in a pre-pass so the done budget is correct regardless of how
    // running/done interleave in dispatch order; a second pass emits the kept
    // rows in dispatch order.
    let runningCount = total - doneCount - failedCount
    let runningBudget = max(0, maxRows - failedCount)
    let runningShown = min(runningCount, runningBudget)
    let doneBudget = max(0, maxRows - failedCount - runningShown)
    let doneShown = min(doneCount, doneBudget)

    var runningPlaced = 0
    var donePlaced = 0
    var visible: [Subagent] = []
    for p in order {
        switch state(of: p) {
        case .failed:
            visible.append(Subagent(id: p.id, label: p.label, state: .failed))
        case .running:
            if runningPlaced < runningShown {
                visible.append(Subagent(id: p.id, label: p.label, state: .running))
                runningPlaced += 1
            }
        case .done:
            if donePlaced < doneShown {
                visible.append(Subagent(id: p.id, label: p.label, state: .done))
                donePlaced += 1
            }
        }
    }
    return SubagentList(
        visible: visible,
        total: total,
        doneCount: doneCount,
        failedCount: failedCount,
        overflowRunning: runningCount - runningShown,
        overflowDone: doneCount - doneShown
    )
```

Use the two-pass version; delete the earlier single-loop draft. Also update the function's doc comment to describe the `.done` state and the settled-clear rule.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SubagentDetectionTests`
Expected: PASS (all tests, including the updated cap tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/SubagentDetection.swift Tests/ClaudeLightCoreTests/SubagentDetectionTests.swift
git commit -m "feat: subagent .done state, batch scoping, X-of-N counts, row cap"
```

---

### Task 2: Chip text — `X of N done · K failed`

**Files:**
- Modify: `Sources/ClaudeLightCore/PanelModel.swift:41-46`
- Test: `Tests/ClaudeLightCoreTests/PanelModelTests.swift:40-53`

**Interfaces:**
- Consumes: `SubagentList` with `total`, `doneCount`, `failedCount` (Task 1).
- Produces: `func subagentChipText(_ list: SubagentList) -> String` returning `"⑂ 3 of 5 done"` or `"⑂ 3 of 5 done · 1 failed"`.

- [ ] **Step 1: Write the failing tests**

Replace the two chip tests in `Tests/ClaudeLightCoreTests/PanelModelTests.swift`:

```swift
func test_subagentChipText_countAndFailed() {
    let list = SubagentList(visible: [], total: 5, doneCount: 3, failedCount: 1,
                            overflowRunning: 0, overflowDone: 0)
    XCTAssertEqual(subagentChipText(list), "⑂ 3 of 5 done · 1 failed")
}

func test_subagentChipText_countNoFailures() {
    let list = SubagentList(visible: [], total: 5, doneCount: 3, failedCount: 0,
                            overflowRunning: 0, overflowDone: 0)
    XCTAssertEqual(subagentChipText(list), "⑂ 3 of 5 done")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PanelModelTests`
Expected: FAIL — output is the old `"⑂ N subagents"` format.

- [ ] **Step 3: Implement the new chip text**

Replace `subagentChipText` in `Sources/ClaudeLightCore/PanelModel.swift`:

```swift
/// Collapsed-subagents chip: "⑂ 3 of 5 done" (· K failed when any failed).
public func subagentChipText(_ list: SubagentList) -> String {
    let base = "⑂ \(list.doneCount) of \(list.total) done"
    return list.failedCount > 0 ? "\(base) · \(list.failedCount) failed" : base
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PanelModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/PanelModel.swift Tests/ClaudeLightCoreTests/PanelModelTests.swift
git commit -m "feat: subagent chip shows X of N done"
```

---

### Task 3: Render the rows — done strikethrough, running pulse dot, `+K done`

**Files:**
- Modify: `Sources/ClaudeLightApp/SessionCard.swift` (`SubagentRows`, ~lines 130-179)
- Modify: `Sources/ClaudeLightApp/PanelContent.swift:23-28` (row-weight estimate)

**Interfaces:**
- Consumes: `SubagentList` (`visible`, `overflowRunning`, `overflowDone`) and `Subagent.State` (`.running`/`.done`/`.failed`) from Task 1; `subagentChipText` from Task 2.
- Produces: no new public API; SwiftUI view changes only.

This task is view code (no unit test — SwiftUI rendering is validated live in Task 4). Keep the existing collapsed/expanded chevron, guide-line rail, and `.plain` button.

- [ ] **Step 1: Add the running pulse-dot subview**

At the end of `Sources/ClaudeLightApp/SessionCard.swift`, add a small view that pulses unless reduced-motion is on:

```swift
/// The live-agent marker: a small orange dot with a gentle pulse. Honors
/// reduce-motion by falling back to a static dot.
private struct LivePulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(PanelPalette.orange)
            .frame(width: 6, height: 6)
            .scaleEffect(animating ? 1.0 : 0.7)
            .opacity(animating ? 1.0 : 0.5)
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                       value: animating)
            .onAppear { if !reduceMotion { animating = true } }
    }
}
```

- [ ] **Step 2: Rewrite the expanded rows and overflow lines**

Replace the `if !collapsed { ... }` block inside `SubagentRows.body` with per-state rendering plus both overflow lines:

```swift
            if !collapsed {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(list.visible, id: \.id) { sub in
                        HStack(spacing: 5) {
                            switch sub.state {
                            case .failed:
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(PanelPalette.red)
                                    .frame(width: 10)
                            case .done:
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 10)
                            case .running:
                                LivePulseDot().frame(width: 10)
                            }
                            Text(sub.label)
                                .font(.system(size: 11))
                                .strikethrough(sub.state == .done)
                                .foregroundStyle(foreground(for: sub.state))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    // The no-color `.strikethrough(_:)` above lets the line
                    // inherit the dimmed tertiary label color — no explicit
                    // color argument needed.
                    if list.overflowRunning > 0 {
                        Text("+\(list.overflowRunning) more running")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    if list.overflowDone > 0 {
                        Text("+\(list.overflowDone) done")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 2)
                }
            }
```

Add the foreground helper inside `SubagentRows`:

```swift
    private func foreground(for state: Subagent.State) -> AnyShapeStyle {
        switch state {
        case .failed:  return AnyShapeStyle(PanelPalette.red)
        case .done:    return AnyShapeStyle(.tertiary)   // dimmed settled tail
        case .running: return AnyShapeStyle(.secondary)  // brighter than done
        }
    }
```

- [ ] **Step 3: Update the panel height estimate for the done overflow line**

In `Sources/ClaudeLightApp/PanelContent.swift`, the row-weight estimate must count both overflow lines so a big done tail can't mis-size the panel. Replace lines 23-28:

```swift
    private var estimatedRowWeight: Int {
        let subagentRows = watcher.subagentsBySession.values.reduce(0) {
            $0 + $1.visible.count
                + ($1.overflowRunning > 0 ? 1 : 0)
                + ($1.overflowDone > 0 ? 1 : 0)
        }
        return watcher.sessions.count + subagentRows / 3
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds (no errors).

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: PASS — all tests green (confirms Task 1/2 model changes didn't regress any consumer).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeLightApp/SessionCard.swift Sources/ClaudeLightApp/PanelContent.swift
git commit -m "feat: render subagent progress rows — done strikethrough, live pulse, +K done"
```

---

### Task 4: Live verification & final review

**Files:** none (verification only).

- [ ] **Step 1: Run the app and drive a fan-out**

Build and launch the menu-bar app, then in a Claude Code session dispatch a parallel fan-out (e.g. several `Task` subagents). Open the panel and confirm against the mockup:
- Collapsed chip reads `⑂ X of N done` and climbs as agents finish.
- Expanded rows show done (`✓`, struck, dimmed), running (orange pulse dot, brighter), failed (`✗`, red), in dispatch order, stable in place.
- A large fan-out (>6 agents) caps at 6 rows with a `+K done` line; the header count stays exact.
- With reduce-motion enabled (System Settings → Accessibility → Display → Reduce motion), the running dot is static.

Use the `/run` skill or the project's launch command; if a launch skill exists, prefer it.

- [ ] **Step 2: Run the full suite one final time**

Run: `swift test`
Expected: PASS.

- [ ] **Step 3: Request code review**

Use `superpowers:requesting-code-review` (or `/code-review`) against the branch diff before opening the PR.

- [ ] **Step 4: Open the PR**

```bash
git push -u origin feat/subagent-progress
gh pr create --title "feat: subagent progress & record (X of N done)" \
  --body "Shows a fan-out's X-of-N progress and a struck-through record of completed subagents, scoped to the since-last-prompt batch. Spec: docs/superpowers/specs/2026-07-05-subagent-progress-design.md"
```

---

## Self-Review

**Spec coverage:**
- `.done` state → Task 1. Batch scoping (clear settled on prompt) → Task 1. Counts on `SubagentList` → Task 1. Row cap (6, failed→running→done, `overflowDone`) → Task 1. Chip `X of N done · K failed` → Task 2. Row rendering (strikethrough/pulse/`+K done`) → Task 3. Panel-height estimate → Task 3. Turn-end lifetime (no `SessionWatcher` change) → honored by omission, noted in plan header. Reduce-motion → Task 3. Live verify → Task 4.
- No spec requirement is left without a task.

**Placeholder scan:** No TBD/TODO; every code step shows complete code. The two "delete the draft / use this form" notes are deliberate corrections within a step, with the final code shown explicitly.

**Type consistency:** `maxRows` used consistently (Task 1 signature + tests). `SubagentList` init argument order (`visible, total, doneCount, failedCount, overflowRunning, overflowDone`) matches across Task 1 struct, Task 1 tests, and Task 2 tests. `Subagent.State` cases `.running/.done/.failed` consistent across Tasks 1 and 3. `foreground(for:)` and `LivePulseDot` are self-contained in Task 3.
