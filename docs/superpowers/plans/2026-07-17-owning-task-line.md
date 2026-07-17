# Owning-Task Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show one line of task context — `▸ <in-progress task subject> · done/total` — above the subagent rows in a running session's card.

**Architecture:** A new pure detection function in HiveLightCore parses the task list from the transcript (latest `task_reminder` snapshot + replay of later `TaskCreate`/`TaskUpdate` events). `SessionWatcher.reload` computes it from the same memoized 4 MB wide read used for subagents and publishes a per-session map; `SessionCard` renders the line. The existing "Show subagents" toggle governs both, relabeled "Show session activity".

**Tech Stack:** Swift Package Manager, XCTest, SwiftUI (macOS MenuBarExtra).

**Spec:** `docs/superpowers/specs/2026-07-17-owning-task-line-design.md`

## Global Constraints

- Never commit to `main`; all work happens on `feat/owning-task-line`, PR when done.
- No AI attribution in commits or the PR body.
- Detection must be defensive: unparseable lines are skipped, never crash (same posture as `SubagentDetection.swift`).
- Subject truncation is 40 characters, matching subagent label truncation.
- The UserDefaults key stays `showSubagents` — only the visible label changes.
- Run `swift test` for verification; the full suite must stay green after every task.

---

### Task 1: `taskSummary(fromTranscript:)` detection (HiveLightCore)

**Files:**
- Create: `Sources/HiveLightCore/TaskSummaryDetection.swift`
- Modify: `Sources/HiveLightCore/SubagentDetection.swift` (extract shared `toolResultText` helper in the refactor step)
- Test: `Tests/HiveLightCoreTests/TaskSummaryDetectionTests.swift`

**Interfaces:**
- Consumes: nothing new (pure function over a JSONL string).
- Produces: `public struct TaskSummary: Equatable, Sendable { let inProgressSubject: String; let doneCount: Int; let total: Int }` and `public func taskSummary(fromTranscript jsonl: String) -> TaskSummary?`. Task 2 and Task 3 rely on exactly these names.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HiveLightCoreTests/TaskSummaryDetectionTests.swift`:

```swift
import XCTest
@testable import HiveLightCore

final class TaskSummaryDetectionTests: XCTestCase {
    // Fixture shapes captured from a real multi-agent transcript (2026-07-17).

    /// Periodic full snapshot of the task list.
    private func reminder(_ items: [(id: String, subject: String, status: String)]) -> String {
        let content = items.map {
            #"{"id":"\#($0.id)","subject":"\#($0.subject)","activeForm":"x","status":"\#($0.status)","blocks":[],"blockedBy":[]}"#
        }.joined(separator: ",")
        return #"{"type":"attachment","attachment":{"type":"task_reminder","content":[\#(content)],"itemCount":\#(items.count)}}"#
    }
    private func emptyReminder() -> String {
        #"{"type":"attachment","attachment":{"type":"task_reminder","content":[],"itemCount":0}}"#
    }
    private func createUse(_ useID: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"\#(useID)","name":"TaskCreate","input":{"subject":"s"}}]}}"#
    }
    private func createResult(_ useID: String, taskID: String, subject: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(useID)","content":"Task #\#(taskID) created successfully: \#(subject)"}]}}"#
    }
    private func updateUse(_ taskID: String, status: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"u-\#(taskID)-\#(status)","name":"TaskUpdate","input":{"taskId":"\#(taskID)","status":"\#(status)"}}]}}"#
    }
    private func join(_ lines: [String]) -> String { lines.joined(separator: "\n") }

    func test_reminderSnapshot_summaryFromInProgress() {
        let t = reminder([("1", "Task 1: types", "completed"),
                          ("2", "Task 2: render", "in_progress"),
                          ("3", "Task 3: backfill", "pending")])
        XCTAssertEqual(taskSummary(fromTranscript: t),
                       TaskSummary(inProgressSubject: "Task 2: render", doneCount: 1, total: 3))
    }

    func test_noInProgress_returnsNil() {
        let t = reminder([("1", "Task 1", "completed"), ("2", "Task 2", "pending")])
        XCTAssertNil(taskSummary(fromTranscript: t))
    }

    func test_emptyTranscript_returnsNil() {
        XCTAssertNil(taskSummary(fromTranscript: ""))
        XCTAssertNil(taskSummary(fromTranscript: "not json\n{bad"))
    }

    func test_replayOnly_createThenUpdate_buildsSummary() {
        let t = join([createUse("c1"), createResult("c1", taskID: "1", subject: "Task 1: types"),
                      createUse("c2"), createResult("c2", taskID: "2", subject: "Task 2: render"),
                      updateUse("1", status: "in_progress"),
                      updateUse("1", status: "completed"),
                      updateUse("2", status: "in_progress")])
        XCTAssertEqual(taskSummary(fromTranscript: t),
                       TaskSummary(inProgressSubject: "Task 2: render", doneCount: 1, total: 2))
    }

    func test_updateAfterSnapshot_completingLastInProgress_returnsNil() {
        let t = join([reminder([("1", "Task 1", "in_progress")]),
                      updateUse("1", status: "completed")])
        XCTAssertNil(taskSummary(fromTranscript: t))
    }

    func test_createAfterSnapshot_appendsToTotal() {
        let t = join([reminder([("1", "Task 1", "in_progress")]),
                      createUse("c7"), createResult("c7", taskID: "7", subject: "Task 7: docs")])
        XCTAssertEqual(taskSummary(fromTranscript: t),
                       TaskSummary(inProgressSubject: "Task 1", doneCount: 0, total: 2))
    }

    func test_multipleInProgress_mostRecentlyUpdatedWins() {
        let t = join([reminder([("1", "Task 1", "in_progress"), ("2", "Task 2", "pending")]),
                      updateUse("2", status: "in_progress")])
        XCTAssertEqual(taskSummary(fromTranscript: t)?.inProgressSubject, "Task 2")
    }

    func test_unknownTaskIdUpdate_ignored() {
        let t = join([reminder([("1", "Task 1", "in_progress")]),
                      updateUse("99", status: "completed")])
        XCTAssertEqual(taskSummary(fromTranscript: t),
                       TaskSummary(inProgressSubject: "Task 1", doneCount: 0, total: 1))
    }

    func test_malformedCreateResult_ignored() {
        let t = join([reminder([("1", "Task 1", "in_progress")]),
                      createUse("c1"),
                      #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"c1","content":"something else entirely"}]}}"#])
        XCTAssertEqual(taskSummary(fromTranscript: t)?.total, 1)
    }

    func test_emptyReminder_doesNotResetState() {
        let t = join([reminder([("1", "Task 1", "in_progress")]), emptyReminder()])
        XCTAssertEqual(taskSummary(fromTranscript: t)?.total, 1)
    }

    func test_laterSnapshot_replacesEarlierState() {
        let t = join([reminder([("1", "Old task", "in_progress")]),
                      reminder([("1", "Task 1", "completed"), ("2", "Task 2", "in_progress")])])
        XCTAssertEqual(taskSummary(fromTranscript: t),
                       TaskSummary(inProgressSubject: "Task 2", doneCount: 1, total: 2))
    }

    func test_longSubject_truncatedTo40() {
        let long = String(repeating: "x", count: 80)
        let t = reminder([("1", long, "in_progress")])
        XCTAssertEqual(taskSummary(fromTranscript: t)?.inProgressSubject.count, 40)
    }

    func test_nonCreateToolResult_withCreateShapedText_ignored() {
        // Only results paired to a TaskCreate tool_use count.
        let t = join([reminder([("1", "Task 1", "in_progress")]),
                      #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"bash-1","content":"Task #9 created successfully: fake"}]}}"#])
        XCTAssertEqual(taskSummary(fromTranscript: t)?.total, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TaskSummaryDetectionTests 2>&1 | tail -5`
Expected: compile error — `cannot find 'taskSummary' in scope` / `cannot find type 'TaskSummary'`.

- [ ] **Step 3: Write the implementation**

Create `Sources/HiveLightCore/TaskSummaryDetection.swift`:

```swift
import Foundation

/// The session's task-list context: the in-progress task plus progress counts.
public struct TaskSummary: Equatable, Sendable {
    public let inProgressSubject: String   // truncated to 40 chars
    public let doneCount: Int
    public let total: Int

    public init(inProgressSubject: String, doneCount: Int, total: Int) {
        self.inProgressSubject = inProgressSubject
        self.doneCount = doneCount
        self.total = total
    }
}

/// Derives the current task list from a transcript (JSONL): the latest
/// populated `task_reminder` attachment is the base snapshot; `TaskCreate`
/// tool_results ("Task #N created successfully: <subject>") and `TaskUpdate`
/// status inputs seen after it are replayed on top, so the summary stays
/// current between reminders. Returns nil when no task state exists or no
/// task is in progress — the panel simply omits the line.
///
/// Ties: with several in-progress tasks, the one touched last (by transcript
/// order; snapshot order for untouched ones) wins. Defensive/fail-safe:
/// unparseable lines are skipped.
public func taskSummary(fromTranscript jsonl: String) -> TaskSummary? {
    struct TaskState { var subject: String; var status: String; var recency: Int }
    var tasks: [String: TaskState] = [:]
    var counter = 0
    var createUses = Set<String>()   // TaskCreate tool_use ids awaiting their result

    for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { continue }

        // A populated reminder is a full snapshot — it replaces all prior state.
        if let att = obj["attachment"] as? [String: Any],
           (att["type"] as? String) == "task_reminder",
           let items = att["content"] as? [[String: Any]], !items.isEmpty {
            tasks.removeAll()
            for item in items {
                guard let id = item["id"] as? String,
                      let subject = item["subject"] as? String,
                      let status = item["status"] as? String else { continue }
                counter += 1
                tasks[id] = TaskState(subject: subject, status: status, recency: counter)
            }
            continue
        }

        guard let message = obj["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { continue }

        for block in content {
            switch block["type"] as? String {
            case "tool_use":
                guard let name = block["name"] as? String else { continue }
                if name == "TaskCreate", let id = block["id"] as? String {
                    createUses.insert(id)
                }
                if name == "TaskUpdate",
                   let input = block["input"] as? [String: Any],
                   let taskID = input["taskId"] as? String,
                   let status = input["status"] as? String,
                   tasks[taskID] != nil {
                    counter += 1
                    tasks[taskID]?.status = status
                    tasks[taskID]?.recency = counter
                }
            case "tool_result":
                guard let useID = block["tool_use_id"] as? String,
                      createUses.remove(useID) != nil,
                      let text = toolResultText(block),
                      let created = parseCreateResult(text),
                      tasks[created.id] == nil else { continue }
                counter += 1
                tasks[created.id] = TaskState(subject: created.subject,
                                              status: "pending", recency: counter)
            default:
                continue
            }
        }
    }

    guard let current = tasks.values
        .filter({ $0.status == "in_progress" })
        .max(by: { $0.recency < $1.recency })
    else { return nil }
    return TaskSummary(
        inProgressSubject: String(current.subject.prefix(40)),
        doneCount: tasks.values.filter { $0.status == "completed" }.count,
        total: tasks.count
    )
}

/// Parses "Task #7 created successfully: <subject>" → (id, subject).
private func parseCreateResult(_ text: String) -> (id: String, subject: String)? {
    guard text.hasPrefix("Task #"),
          let sep = text.range(of: " created successfully: ") else { return nil }
    let id = String(text[text.index(text.startIndex, offsetBy: 6)..<sep.lowerBound])
    guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
    let subject = String(text[sep.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !subject.isEmpty else { return nil }
    return (id, subject)
}

/// The plain text of a tool_result block — string content or the first text
/// block of block-array content.
func toolResultText(_ block: [String: Any]) -> String? {
    if let s = block["content"] as? String { return s }
    if let blocks = block["content"] as? [[String: Any]],
       let first = blocks.first(where: { ($0["type"] as? String) == "text" }),
       let s = first["text"] as? String { return s }
    return nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TaskSummaryDetectionTests 2>&1 | tail -3`
Expected: `Executed 13 tests, with 0 failures`.

- [ ] **Step 5: Refactor — reuse `toolResultText` in `SubagentDetection.swift`**

In `Sources/HiveLightCore/SubagentDetection.swift`, replace the body of `isBackgroundLaunchAck` so text extraction goes through the shared helper:

```swift
/// The immediate ack a background agent dispatch gets while the agent keeps
/// working — it must not settle the agent.
private func isBackgroundLaunchAck(_ block: [String: Any]) -> Bool {
    guard (block["is_error"] as? Bool) != true,
          let text = toolResultText(block) else { return false }
    return text.hasPrefix("Async agent launched successfully")
}
```

- [ ] **Step 6: Run the full suite**

Run: `swift test 2>&1 | grep "Executed" | tail -1`
Expected: all tests pass, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/HiveLightCore/TaskSummaryDetection.swift Sources/HiveLightCore/SubagentDetection.swift Tests/HiveLightCoreTests/TaskSummaryDetectionTests.swift
git commit -m "feat: derive task-list summary from transcript (snapshot + replay)"
```

---

### Task 2: `taskLineText` formatting helper (HiveLightCore)

**Files:**
- Modify: `Sources/HiveLightCore/PanelModel.swift` (append at end of file)
- Test: `Tests/HiveLightCoreTests/PanelModelTests.swift` (append test)

**Interfaces:**
- Consumes: `TaskSummary` from Task 1.
- Produces: `public func taskLineText(_ summary: TaskSummary) -> String`. Task 4's view renders exactly this string (the `▸` glyph is view chrome, not part of the string).

- [ ] **Step 1: Write the failing test**

Append to `Tests/HiveLightCoreTests/PanelModelTests.swift` (inside the test class):

```swift
    func test_taskLineText_subjectDotCounts() {
        let summary = TaskSummary(inProgressSubject: "Task 6: AGENTS.md docs + quality gate",
                                  doneCount: 5, total: 7)
        XCTAssertEqual(taskLineText(summary), "Task 6: AGENTS.md docs + quality gate · 5/7")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PanelModelTests.test_taskLineText_subjectDotCounts 2>&1 | tail -3`
Expected: compile error — `cannot find 'taskLineText' in scope`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/HiveLightCore/PanelModel.swift`:

```swift
/// The owning-task line under a session row: "<subject> · done/total".
public func taskLineText(_ summary: TaskSummary) -> String {
    "\(summary.inProgressSubject) · \(summary.doneCount)/\(summary.total)"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PanelModelTests 2>&1 | tail -3`
Expected: all PanelModelTests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/HiveLightCore/PanelModel.swift Tests/HiveLightCoreTests/PanelModelTests.swift
git commit -m "feat: task-line text formatting helper"
```

---

### Task 3: SessionWatcher wiring — one scan, two results

**Files:**
- Modify: `Sources/HiveLightApp/SessionWatcher.swift`

**Interfaces:**
- Consumes: `taskSummary(fromTranscript:)` and `TaskSummary` from Task 1; existing `subagents(fromTranscript:)`, `FileMemoCache`, `readTranscript`.
- Produces: `@Published private(set) var taskSummaryBySession: [String: TaskSummary]` — Task 4's views read this map.

No new unit test: `SessionWatcher` is the untested UI-glue layer (existing convention); correctness is carried by the Core tests plus the live verification in Task 5. Build + full suite must stay green.

- [ ] **Step 1: Widen the memo cache to hold both scan results**

In `Sources/HiveLightApp/SessionWatcher.swift`, replace the cache property (line ~67):

```swift
    private let subagentCache = FileMemoCache<SubagentList>()
```

with:

```swift
    /// One wide transcript read yields both activity results — memoized
    /// together so tasks add no extra I/O.
    private struct TranscriptScan {
        let subagents: SubagentList
        let taskSummary: TaskSummary?
    }
    private let transcriptScanCache = FileMemoCache<TranscriptScan>()
```

- [ ] **Step 2: Publish the per-session task map**

Next to the existing `@Published` maps (near `subagentsBySession`), add:

```swift
    @Published private(set) var taskSummaryBySession: [String: TaskSummary] = [:]
```

- [ ] **Step 3: Compute both results in `reload()`**

In `reload()` (line ~156), add a local map next to `subagentMap`:

```swift
        var taskMap: [String: TaskSummary] = [:]
```

Replace the scan block:

```swift
            if showSubagents, let stamp = fileStamp(path: path) {
                // The wide tail read is expensive (up to 4 MB per reload); memoize
                // the parsed list until the transcript's (mtime, size) changes.
                let list = subagentCache.value(for: path, stamp: stamp) {
                    guard let wide = readTranscript(atPath: path, maxBytes: 4 * 1024 * 1024)
                    else { return .empty }
                    return subagents(fromTranscript: wide)
                }
                if !list.isEmpty { subagentMap[live[i].sessionID] = list }
                scannedTranscripts.insert(path)
            }
```

with:

```swift
            if showSubagents, let stamp = fileStamp(path: path) {
                // The wide tail read is expensive (up to 4 MB per reload); memoize
                // the parsed results until the transcript's (mtime, size) changes.
                let scan = transcriptScanCache.value(for: path, stamp: stamp) {
                    guard let wide = readTranscript(atPath: path, maxBytes: 4 * 1024 * 1024)
                    else { return TranscriptScan(subagents: .empty, taskSummary: nil) }
                    return TranscriptScan(subagents: subagents(fromTranscript: wide),
                                          taskSummary: taskSummary(fromTranscript: wide))
                }
                if !scan.subagents.isEmpty { subagentMap[live[i].sessionID] = scan.subagents }
                if let summary = scan.taskSummary { taskMap[live[i].sessionID] = summary }
                scannedTranscripts.insert(path)
            }
```

Update the eviction line to the renamed cache:

```swift
        transcriptScanCache.evict(keeping: scannedTranscripts)
```

And publish the map next to `self.subagentsBySession = subagentMap`:

```swift
        self.taskSummaryBySession = taskMap
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep "Executed" | tail -1`
Expected: build succeeds; all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/HiveLightApp/SessionWatcher.swift
git commit -m "feat: publish per-session task summary from the shared transcript scan"
```

---

### Task 4: Render the line + relabel the toggle

**Files:**
- Modify: `Sources/HiveLightApp/SessionCard.swift`
- Modify: `Sources/HiveLightApp/PanelContent.swift`
- Modify: `Sources/HiveLightApp/SettingsPane.swift:52`

**Interfaces:**
- Consumes: `taskSummaryBySession` (Task 3), `taskLineText` (Task 2).
- Produces: user-visible card row; no downstream consumers.

UI layer — no unit test (existing convention: SwiftUI views are verified live). Build + suite green, live check in Task 5.

- [ ] **Step 1: Add the property and row to `SessionCard`**

In `Sources/HiveLightApp/SessionCard.swift`, add the property after `let subagents: SubagentList?` (line ~35):

```swift
    let taskSummary: TaskSummary?
```

In `card` (line ~117), insert the task line *before* the subagent block:

```swift
            if let summary = taskSummary {
                // Owning-task context: which tracker task the session is on,
                // plus list progress. One info kind, one treatment, fixed slot
                // above the fan-out (renders with or without one).
                HStack(spacing: 4) {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.tertiary)
                    Text(taskLineText(summary))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.leading, 18)
                .padding(.top, 2)
            }
            if let list = subagents, !list.isEmpty {
                SubagentRows(list: list, collapsed: $subagentsCollapsed)
                    .padding(.leading, 18)
                    .padding(.top, 3)
            }
```

In the `accessibilityLabel` array (line ~135), add the task line after the subtitle entry:

```swift
        .accessibilityLabel([HiveLightCore.accessibilityLabel(for: session),
                             cardSubtitle(for: session, errorReason: errorReason),
                             taskSummary.map { "task \(taskLineText($0))" },
                             session.model.map { "model \(shortModelName($0))" },
                             session.contextFraction.map { contextTooltip(fraction: $0) }]
                            .compactMap { $0 }.joined(separator: ". "))
```

- [ ] **Step 2: Pass the summary through `PanelContent`**

In `Sources/HiveLightApp/PanelContent.swift`, `card(_:now:grouped:)` (line ~176):

```swift
    private func card(_ session: Session, now: Date, grouped: Bool) -> some View {
        SessionCard(session: session,
                    errorReason: watcher.errorReasons[session.sessionID],
                    subagents: watcher.subagentsBySession[session.sessionID],
                    taskSummary: watcher.taskSummaryBySession[session.sessionID],
                    now: now,
                    grouped: grouped)
    }
```

If any other `SessionCard(...)` call sites exist (previews), pass `taskSummary: nil`.

- [ ] **Step 3: Fold task lines into the pre-layout size estimate**

`MenuBarExtra` panels take their IDEAL height pre-layout — every new row must be
counted or tall panels clip. In `estimatedRowWeight` (line ~26), count task
lines like subagent mini-rows (~1/3 card height each):

```swift
    private var estimatedRowWeight: Int {
        let subagentRows = watcher.subagentsBySession.values.reduce(0) {
            // A large fan-out's block scrolls internally (height-bounded at ~8
            // rows), so cap its contribution to the panel-size estimate.
            $0 + min($1.visible.count, 8)
        }
        // Task lines weigh the same as subagent mini-rows.
        let taskRows = watcher.taskSummaryBySession.count
        let usageRow = usageRowVisible ? 1 : 0
        // Grouped mode adds one ~14pt header per block (~1/3 card height).
        let headerRows = watcher.sessionOrder == .project
            ? (sessionBlocks(watcher.sessions).count + 2) / 3 : 0
        return watcher.sessions.count + (subagentRows + taskRows) / 3 + usageRow + headerRows
    }
```

- [ ] **Step 4: Relabel the toggle**

In `Sources/HiveLightApp/SettingsPane.swift:52`, change:

```swift
                    MiniSwitch(isOn: $watcher.showSubagents, label: "Show subagents")
```

to:

```swift
                    MiniSwitch(isOn: $watcher.showSubagents, label: "Show session activity")
```

(The defaults key stays `showSubagents` — label only.)

- [ ] **Step 5: Build and run the full suite**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep "Executed" | tail -1`
Expected: build succeeds; all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/HiveLightApp/SessionCard.swift Sources/HiveLightApp/PanelContent.swift Sources/HiveLightApp/SettingsPane.swift
git commit -m "feat: owning-task line above the subagent fan-out; relabel toggle"
```

---

### Task 5: Live verification and PR

**Files:**
- None committed (scratch test is created and deleted).

**Interfaces:**
- Consumes: everything above.
- Produces: opened PR from `feat/owning-task-line` to `main`.

- [ ] **Step 1: Scratch-verify detection against a real transcript**

Create `Tests/HiveLightCoreTests/ScratchRealTranscriptTest.swift` (NOT committed):

```swift
import XCTest
@testable import HiveLightCore

final class ScratchRealTranscriptTest: XCTestCase {
    func test_realTaskTranscript() throws {
        // Newest transcript of a task-driven session; adjust to any current one.
        let path = "/Users/fernandocastillo/.claude/projects/-Users-fernandocastillo-Projects-ALPHEYA-ai-agent-hub--claude-worktrees-feat-AT-5163-persist-canvas-computed-performance/ee2b97f3-d9a7-409a-80a5-320897f7befe.jsonl"
        let jsonl = try String(contentsOfFile: path, encoding: .utf8)
        print("SCRATCH taskSummary:", taskSummary(fromTranscript: jsonl) as Any)
        print("SCRATCH subagents:", subagents(fromTranscript: jsonl).visible.map(\.label))
    }
}
```

Run: `swift test --filter ScratchRealTranscriptTest 2>&1 | grep SCRATCH`
Expected: a non-nil `TaskSummary` whose subject matches the session's current
in-progress task (cross-check against the terminal), sane done/total counts.
If the session's task list is already fully completed, expect nil AND verify
via a truncated copy of the transcript ending mid-task instead.

Then: `rm Tests/HiveLightCoreTests/ScratchRealTranscriptTest.swift`

- [ ] **Step 2: Full suite, final check**

Run: `swift test 2>&1 | grep "Executed" | tail -1`
Expected: 0 failures.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin feat/owning-task-line
gh pr create --title "feat: owning-task line in the session card" --body "..."
```

PR body: summarize the spec (problem, what renders, data source, settings
relabel) and the test evidence. **No AI attribution anywhere.**

---

## Self-Review

- **Spec coverage:** rendering rule (Task 4 step 1), nil/hide semantics (Task 1 detection + Task 4 `if let`), snapshot+replay (Task 1), most-recent-wins (Task 1), 40-char truncation (Task 1), shared 4 MB read + memo (Task 3), settings relabel w/ stable key (Task 4 step 4), height estimate (Task 4 step 3), live verify (Task 5). Covered.
- **Placeholder scan:** PR body says "..." — intentional: content is specified in prose directly below it. No TBDs elsewhere.
- **Type consistency:** `TaskSummary` / `taskSummary(fromTranscript:)` / `taskLineText(_:)` / `taskSummaryBySession` used identically across Tasks 1–5.
