# Notification Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The needs-you notification shows *what* is being asked — the pending question, the ask sentence, or the permission message — instead of a generic status label (#80).

**Architecture:** The hook extracts a short `detail` string at status-write time (question text from the transcript, or the Notification payload's message), stores it in the session JSON, and the app uses `detail ?? friendlyStatusLabel` as the notification body. Extraction lives in pure Core functions; `HookAction.set` carries the detail alongside the status.

**Tech Stack:** Swift 5.9 (SwiftPM), XCTest.

**Spec:** `docs/superpowers/specs/2026-07-04-notification-detail-design.md`

## Global Constraints

- Work on branch `feat/notification-detail` (already created). Never commit to `main`.
- No AI attribution anywhere: no `Co-Authored-By` trailers, no "Generated with" footers in commits or PRs.
- Exact values: truncation cap is 140 characters (then a single `…`); ExitPlanMode's detail is exactly `"plan ready for review"`; the session JSON key is `detail`.
- Details are truncated at extraction (in `action(for:)`), not at display.
- Menu rows unchanged — detail appears only in the notification body.
- Run `swift test` before each commit — zero failures; `swift build` must also pass (App target).

---

### Task 1: Extraction primitives — `pendingUserQuestionText`, `finalSentence`, `truncatedDetail`

**Files:**
- Modify: `Sources/ClaudeLightCore/PendingQuestionDetection.swift`
- Modify: `Sources/ClaudeLightCore/QuestionDetection.swift`
- Test: `Tests/ClaudeLightCoreTests/PendingQuestionDetectionTests.swift`, `Tests/ClaudeLightCoreTests/QuestionDetectionTests.swift`

**Interfaces:**
- Produces: `public func pendingUserQuestionText(transcriptJSONL: String) -> String?` — the question text of the last still-pending blocking tool_use, nil when none (same supersede/answer semantics as today's boolean). `public func finalSentence(_ text: String) -> String?` — last sentence of code-stripped prose, nil if empty. `public func truncatedDetail(_ text: String) -> String` — ≤140 chars, `…`-terminated when cut. `hasPendingUserQuestion` remains as a one-line wrapper (`!= nil`) so Task 1 compiles standalone; Task 2 deletes it.

- [ ] **Step 1: Write the failing tests**

In `Tests/ClaudeLightCoreTests/PendingQuestionDetectionTests.swift`, add fixture builders next to the existing ones (top of the class):

```swift
    private func askQuestions(id: String, questions: [String]) -> String {
        let qs = questions.map { #"{"question":"\#($0)"}"# }.joined(separator: ",")
        return #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","id":"\#(id)","input":{"questions":[\#(qs)]}}]}}"#
    }
    private func askSingle(id: String, question: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","id":"\#(id)","input":{"question":"\#(question)"}}]}}"#
    }
```

and add these tests:

```swift
    func test_questionText_pendingAskUserQuestion_returnsQuestion() {
        let t = [userPrompt("go"),
                 askQuestions(id: "q1", questions: ["Which database should we use?"])].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "Which database should we use?")
    }

    func test_questionText_singleQuestionKey_returnsQuestion() {
        let t = [userPrompt("go"),
                 askSingle(id: "q1", question: "Deploy now?")].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "Deploy now?")
    }

    func test_questionText_multipleQuestions_marksMore() {
        let t = [userPrompt("go"),
                 askQuestions(id: "q1", questions: ["First?", "Second?", "Third?"])].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "First? (+2 more)")
    }

    func test_questionText_answered_returnsNil() {
        let t = [userPrompt("go"),
                 askQuestions(id: "q1", questions: ["Which?"]),
                 toolResult(id: "q1")].joined(separator: "\n")
        XCTAssertNil(pendingUserQuestionText(transcriptJSONL: t))
    }

    func test_questionText_supersededByNewPrompt_returnsNil() {
        let t = [userPrompt("go"),
                 askQuestions(id: "q1", questions: ["Which?"]),
                 userPrompt("never mind")].joined(separator: "\n")
        XCTAssertNil(pendingUserQuestionText(transcriptJSONL: t))
    }

    func test_questionText_lastPendingWins() {
        let t = [userPrompt("go"),
                 askQuestions(id: "q1", questions: ["Old?"]),
                 askQuestions(id: "q2", questions: ["New?"])].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "New?")
    }

    func test_questionText_exitPlanMode_isFixedLabel() {
        let t = [userPrompt("plan it"),
                 toolUse("ExitPlanMode", id: "p1")].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "plan ready for review")
    }

    func test_questionText_askWithoutText_fallsBackToMarker() {
        // The existing `toolUse` fixture has empty input {}.
        let t = [userPrompt("go"),
                 toolUse("AskUserQuestion", id: "q1")].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "question pending")
    }
```

In `Tests/ClaudeLightCoreTests/QuestionDetectionTests.swift`, add:

```swift
    func test_finalSentence_returnsLastSentence() {
        XCTAssertEqual(finalSentence("I did the thing. Should I also update the docs?"),
                       "Should I also update the docs?")
    }

    func test_finalSentence_stripsCode() {
        XCTAssertEqual(finalSentence("Run ```rm -rf tmp?``` first. Proceed?"), "Proceed?")
    }

    func test_finalSentence_singleSentence_returnsIt() {
        XCTAssertEqual(finalSentence("Deploy to production?"), "Deploy to production?")
    }

    func test_finalSentence_empty_returnsNil() {
        XCTAssertNil(finalSentence(""))
        XCTAssertNil(finalSentence("```only code```"))
    }

    func test_truncatedDetail_shortUnchanged() {
        XCTAssertEqual(truncatedDetail("Deploy?"), "Deploy?")
    }

    func test_truncatedDetail_capsAt140WithEllipsis() {
        let long = String(repeating: "a", count: 200)
        let out = truncatedDetail(long)
        XCTAssertEqual(out.count, 140)
        XCTAssertTrue(out.hasSuffix("…"))
    }

    func test_truncatedDetail_exactly140_unchanged() {
        let s = String(repeating: "b", count: 140)
        XCTAssertEqual(truncatedDetail(s), s)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'pendingUserQuestionText' in scope` (and `finalSentence`, `truncatedDetail`).

- [ ] **Step 3: Implement**

`Sources/ClaudeLightCore/PendingQuestionDetection.swift` — replace the body of the file's public API (keep `blockingQuestionTools` and `isRealUserPrompt` as they are):

Replace `hasPendingUserQuestion` with:

```swift
/// True when the transcript ends with an unanswered blocking question.
/// Thin wrapper over `pendingUserQuestionText` (same semantics).
public func hasPendingUserQuestion(transcriptJSONL: String) -> Bool {
    pendingUserQuestionText(transcriptJSONL: transcriptJSONL) != nil
}

/// The question text of the LAST still-unanswered blocking tool_use — an
/// `AskUserQuestion` (its input's question text) or `ExitPlanMode` (fixed
/// "plan ready for review") with no tool_result since the last real user
/// prompt. Nil when nothing is pending. A later user prompt supersedes
/// stale questions left by interrupted turns. Defensive/fail-safe:
/// unparseable lines are skipped.
public func pendingUserQuestionText(transcriptJSONL: String) -> String? {
    var pending: [(id: String, text: String)] = []

    for line in transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any]
        else { continue }

        if isRealUserPrompt(obj: obj, message: message) {
            pending.removeAll()
            continue
        }

        guard let blocks = message["content"] as? [[String: Any]] else { continue }
        for block in blocks {
            switch block["type"] as? String {
            case "tool_use":
                if let name = block["name"] as? String, blockingQuestionTools.contains(name),
                   let id = block["id"] as? String {
                    pending.removeAll { $0.id == id }
                    pending.append((id, questionText(toolName: name,
                                                     input: block["input"] as? [String: Any])))
                }
            case "tool_result":
                if let id = block["tool_use_id"] as? String {
                    pending.removeAll { $0.id == id }
                }
            default:
                continue
            }
        }
    }
    return pending.last?.text
}

/// Human-readable text for a blocking tool_use. AskUserQuestion carries its
/// question(s) in the input (both the flat `question` and the current
/// `questions` array shapes are seen in transcripts); ExitPlanMode is a
/// fixed label. Falls back to a marker so detection never loses a pending
/// question just because its text is missing.
private func questionText(toolName: String, input: [String: Any]?) -> String {
    if toolName == "ExitPlanMode" { return "plan ready for review" }
    if let q = input?["question"] as? String { return q }
    if let qs = input?["questions"] as? [[String: Any]] {
        let texts = qs.compactMap { $0["question"] as? String }
        if let first = texts.first {
            return texts.count > 1 ? "\(first) (+\(texts.count - 1) more)" : first
        }
    }
    return "question pending"
}
```

`Sources/ClaudeLightCore/QuestionDetection.swift` — append:

```swift
/// The last sentence of the code-stripped prose — the question/ask itself,
/// for notification bodies. Nil when nothing prose-like remains.
public func finalSentence(_ text: String) -> String? {
    let prose = strippingCode(text).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prose.isEmpty else { return nil }
    var sentences: [String] = []
    var current = ""
    for ch in prose {
        current.append(ch)
        if ch == "." || ch == "!" || ch == "?" {
            sentences.append(current)
            current = ""
        }
    }
    if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        sentences.append(current)
    }
    let last = sentences.last?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (last?.isEmpty ?? true) ? nil : last
}

/// Caps a notification detail at 140 characters (ellipsis-terminated when
/// cut) so session files stay small and banners stay readable.
public func truncatedDetail(_ text: String) -> String {
    guard text.count > 140 else { return text }
    return String(text.prefix(139)) + "…"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: all tests pass, zero failures (existing boolean-based tests still pass through the wrapper).

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: extract pending-question text and final-sentence details (#80)"
```

---

### Task 2: Thread `detail` end-to-end — HookAction, Session, ApplyHook, notification body

**Files:**
- Modify: `Sources/ClaudeLightCore/HookAction.swift`
- Modify: `Sources/ClaudeLightCore/Session.swift` (struct + CodingKeys)
- Modify: `Sources/ClaudeLightCore/ApplyHook.swift:8-27`
- Modify: `Sources/ClaudeLightCore/PendingQuestionDetection.swift` (delete the `hasPendingUserQuestion` wrapper)
- Modify: `Sources/ClaudeLightApp/SessionWatcher.swift:173-178` (notification body)
- Test: `Tests/ClaudeLightCoreTests/HookActionTests.swift`, `Tests/ClaudeLightCoreTests/PendingQuestionDetectionTests.swift`, `Tests/ClaudeLightCoreTests/ApplyHookTests.swift`

**Interfaces:**
- Consumes: `pendingUserQuestionText`, `finalSentence`, `truncatedDetail` (Task 1).
- Produces: `HookAction.set(SessionStatus, detail: String?)` (no default — Swift enums can't); `Session.detail: String?` (JSON key `detail`, init default nil as the LAST init parameter); notification body = `session.detail ?? friendlyStatusLabel(for:)` for non-error statuses.

- [ ] **Step 1: Update the enum, mapping, schema, apply, and body**

`Sources/ClaudeLightCore/HookAction.swift` — full new content:

```swift
import Foundation

public enum HookAction: Equatable, Sendable {
    case set(SessionStatus, detail: String?)
    case ignore
}

public func action(for payload: HookPayload, transcriptJSONL: String? = nil) -> HookAction {
    switch payload.hookEventName {
    case "SessionStart":
        return .set(.idle, detail: nil)
    case "Stop":
        if let t = transcriptJSONL {
            // Structural signal first: an unanswered AskUserQuestion/ExitPlanMode
            // is unambiguous (#56). The text heuristics remain as fallback.
            if let question = pendingUserQuestionText(transcriptJSONL: t) {
                return .set(.attention, detail: truncatedDetail(question))
            }
            if let last = lastAssistantText(transcriptJSONL: t) {
                if textEndsWithQuestion(last) {
                    return .set(.attention, detail: finalSentence(last).map(truncatedDetail))
                }
                if textEndsWithHandoffAsk(last) {
                    return .set(.handoff, detail: finalSentence(last).map(truncatedDetail))
                }
            }
        }
        return .set(.idle, detail: nil)
    case "UserPromptSubmit", "PreToolUse":
        return .set(.running, detail: nil)
    case "Notification":
        // The payload message says what's blocked ("Claude needs your
        // permission to use Bash") — carry it into the banner (#80).
        return .set(.waiting, detail: payload.message.map(truncatedDetail))
    case "SessionEnd":
        // Tombstone, not delete: the row lingers briefly as "done" (#54).
        // The app removes the file after doneLingerWindow.
        return .set(.done, detail: nil)
    default:
        return .ignore
    }
}
```

`Sources/ClaudeLightCore/PendingQuestionDetection.swift` — delete the `hasPendingUserQuestion` wrapper (and its doc comment); `pendingUserQuestionText` is now the only public entry point.

`Sources/ClaudeLightCore/Session.swift` — add the property after `focusURL`:

```swift
    /// What the session is blocked on, for notification bodies — the pending
    /// question / ask sentence / permission message (#80). Set by the hook
    /// only for needs-you statuses; ≤140 chars.
    public var detail: String?
```

add `detail: String? = nil` as the LAST parameter of the memberwise init (with `self.detail = detail`), and add `case detail` to CodingKeys.

`Sources/ClaudeLightCore/ApplyHook.swift` — the switch becomes:

```swift
    case .set(let status, let detail):
```

and the `Session(...)` construction gains `detail: detail` as its last argument.

`Sources/ClaudeLightApp/SessionWatcher.swift:173-178` — the body line becomes:

```swift
                let body = session.status == .error
                    ? "API error: \(reasons[session.sessionID] ?? "api error")"
                    : (session.detail ?? friendlyStatusLabel(for: session.status))
```

- [ ] **Step 2: Update the broken call sites and add the new tests**

Mechanical updates (the compiler's error list is the checklist):

- `Tests/ClaudeLightCoreTests/HookActionTests.swift` — every `.set(.x)` gains `, detail:`. The exact expectations:
  - `SessionStart` → `.set(.idle, detail: nil)`
  - `Stop`+nil transcript → `.set(.idle, detail: nil)`
  - line 19 (trailing-question heuristic, fixture asks a short question) → `.set(.attention, detail: finalSentence(<the fixture's text>).map(truncatedDetail))` — read the fixture at the top of that test and inline the expected sentence string instead of calling helpers, e.g. if the fixture text is `"Should I continue?"` expect `.set(.attention, detail: "Should I continue?")`
  - line 24 (non-question) → `.set(.idle, detail: nil)`
  - `UserPromptSubmit`/`PreToolUse` → `.set(.running, detail: nil)`
  - `Notification` with message `"anything"` → `.set(.waiting, detail: "anything")`
  - `Notification` without message → `.set(.waiting, detail: nil)`
  - `SessionEnd` → `.set(.done, detail: nil)`
  - handoff fixtures → `.set(.handoff, detail: <the fixture's final sentence>)` (inline the expected string per fixture)
- `Tests/ClaudeLightCoreTests/PendingQuestionDetectionTests.swift` — the remaining `hasPendingUserQuestion` assertions become `XCTAssertNotNil(pendingUserQuestionText(...))` / `XCTAssertNil(...)`; the two Stop-wiring tests (lines ~75, ~84) become `.set(.attention, detail: "question pending")` (the empty-input fixture) and `.set(.idle, detail: nil)`.

New tests in `Tests/ClaudeLightCoreTests/ApplyHookTests.swift`:

```swift
    func test_notificationDetail_isWrittenToSession() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "Notification", cwd: "/x/p",
                            message: "Claude needs your permission to use Bash")
        try applyHook(p, to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.detail,
                       "Claude needs your permission to use Bash")
    }

    func test_runningWrite_clearsStaleDetail() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Notification", cwd: "/x/p",
                                  message: "permission?"), to: store, now: now)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p",
                                  message: nil), to: store, now: now.addingTimeInterval(1))
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(s.status, .running)
        XCTAssertNil(s.detail)
    }
```

- [ ] **Step 3: Run the suite and build**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" && swift build 2>&1 | tail -1`
Expected: all tests pass (count grows by 2), `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: carry the pending question into the needs-you notification (#80)"
```

---

### Task 3: End-to-end verification with the debug binary

**Files:** none (verification only)

**Interfaces:**
- Consumes: the complete branch (Tasks 1–2).

Do NOT quit or replace `/Applications/Claude Light.app`; the debug binary runs alongside it. Make sure "Notify when a session needs you" is enabled (it's the existing Settings toggle; the debug app shares UserDefaults? No — unbundled builds have their own defaults domain, and `SessionNotifier.available` is false for unbundled binaries, so notifications can't post from the bare debug binary).

Because unbundled dev builds compile notifications out (`SessionNotifier.available` requires a bundle), verify via the packaged app instead:

- [ ] **Step 1: Package and launch the dev bundle**

```bash
bash scripts/package-app.sh >/dev/null && open "dist/Claude Light.app"
```

Expected: a second menu-bar icon appears (this dev bundle is unsigned — notification *registration* may be blocked for unsigned apps on this machine; if macOS shows no permission prompt and posts nothing, fall back to Step 1-alt below and verify the session-file plumbing only).

- [ ] **Step 2: Simulate a permission-block with detail**

```bash
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > ~/.claude-light/sessions/detail-e2e.json <<EOF
{"cwd":"/tmp/detail-e2e","status":"running","updated_at":"$NOW","session_id":"detail-e2e","project":"detail-e2e","tty":"ttys997"}
EOF
sleep 3
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > ~/.claude-light/sessions/detail-e2e.json <<EOF
{"cwd":"/tmp/detail-e2e","status":"waiting","updated_at":"$NOW","session_id":"detail-e2e","project":"detail-e2e","tty":"ttys997","detail":"Claude needs your permission to use Bash"}
EOF
```

Expected: notification banner titled `detail-e2e` with body `Claude needs your permission to use Bash` (not "waiting for permission").

**Step 1-alt (if unsigned-registration blocks banners):** verify the plumbing without UI — run the hook binary directly against a fixture transcript and confirm the session file carries `detail`:

```bash
tmp=$(mktemp -d)
cat > "$tmp/t.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"go"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","id":"q1","input":{"questions":[{"question":"Which environment should I deploy to?"}]}}]}}
EOF
echo "{\"session_id\":\"detail-hook-e2e\",\"hook_event_name\":\"Stop\",\"cwd\":\"/tmp/x\",\"transcript_path\":\"$tmp/t.jsonl\"}" | .build/debug/claude-light-hook
cat ~/.claude-light/sessions/detail-hook-e2e.json
rm -f ~/.claude-light/sessions/detail-hook-e2e.json && rm -rf "$tmp"
```

(Build first with `swift build` if needed; check `Sources/claude-light-hook/main.swift` for the exact stdin contract if the invocation errors.)
Expected: the printed session JSON contains `"status":"attention"` and `"detail":"Which environment should I deploy to?"`.

- [ ] **Step 3: Clean up**

```bash
osascript -e 'quit app "dist/Claude Light.app"' 2>/dev/null; pkill -f "dist/Claude Light.app/Contents/MacOS/ClaudeLightApp" 2>/dev/null
rm -f ~/.claude-light/sessions/detail-e2e.json
```

Record observations in the task report; no commit.

---

## After all tasks

Push and open the PR (controller/user step): title `feat: show the pending question in the needs-you notification`, body summarizing extraction + schema + display, `Closes #80`.
