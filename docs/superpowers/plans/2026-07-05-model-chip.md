# Model Chip Implementation Plan (#105)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Session cards show the session's model as a small chip at the subtitle row's trailing edge.

**Architecture:** The hook lifts the last assistant entry's `model` id from the transcript tail it already loads (#96 pass), persists it in the session JSON with `context_fraction`-style merge semantics, and SessionCard renders the short name as a quiet capsule chip. Spec: `docs/superpowers/specs/2026-07-05-model-chip-design.md`.

**Tech Stack:** Swift 5 / Foundation, XCTest, SwiftUI (chip only).

## Global Constraints

- No subprocess and no new I/O in the hook path — `lastModelID` parses the transcript string already in memory.
- Session-JSON key is `model`; absent key must decode (old hooks); additive only.
- Merge semantics: transcript in hand → fresh `lastModelID` result, falling back to the stored value when extraction finds none; no transcript → stored value survives (same as `contextFraction`).
- Short names: "claude-fable-5" → "fable-5", "claude-sonnet-5" → "sonnet-5", "claude-haiku-4-5-20251001" → "haiku-4.5", "claude-opus-4-8" → "opus-4.8", unknown ids pass through.
- Chip: 9pt semibold uppercase, tertiary text, primary-9% capsule (4pt radius), trailing edge of the subtitle row, `layoutPriority(1)` so the left text truncates and the chip never compresses; full raw id in `.help`; card VoiceOver label appends "model <short name>". No chip when `model` nil.
- Run tests with `swift test 2>&1 | grep -E "Executed [0-9]+ tests"`; SourceKit diagnostics are permanently stale — ignore them.

---

### Task 1: `lastModelID` + `shortModelName` (Core)

**Files:**
- Create: `Sources/ClaudeLightCore/ModelInfo.swift`
- Test: `Tests/ClaudeLightCoreTests/ModelInfoTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public func lastModelID(transcriptJSONL: String) -> String?`, `public func shortModelName(_ raw: String) -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ClaudeLightCore

final class ModelInfoTests: XCTestCase {
    private func entry(model: String?, type: String = "assistant") -> String {
        let modelField = model.map { #""model":"\#($0)","# } ?? ""
        return #"{"type":"\#(type)","message":{"role":"\#(type)",\#(modelField)"usage":{"input_tokens":10}}}"#
    }

    func test_lastAssistantModelWins() {
        let jsonl = entry(model: "claude-sonnet-5") + "\n" + entry(model: "claude-fable-5")
        XCTAssertEqual(lastModelID(transcriptJSONL: jsonl), "claude-fable-5")
    }

    func test_skipsNonAssistantAndCorruptLines() {
        let jsonl = entry(model: "claude-fable-5") + "\n"
            + entry(model: "claude-haiku-4-5-20251001", type: "user") + "\n"
            + "not json"
        XCTAssertEqual(lastModelID(transcriptJSONL: jsonl), "claude-fable-5")
    }

    func test_noModelAnywhere_isNil() {
        XCTAssertNil(lastModelID(transcriptJSONL: entry(model: nil)))
        XCTAssertNil(lastModelID(transcriptJSONL: ""))
    }

    func test_shortModelName() {
        XCTAssertEqual(shortModelName("claude-fable-5"), "fable-5")
        XCTAssertEqual(shortModelName("claude-sonnet-5"), "sonnet-5")
        XCTAssertEqual(shortModelName("claude-haiku-4-5-20251001"), "haiku-4.5")
        XCTAssertEqual(shortModelName("claude-opus-4-8"), "opus-4.8")
        XCTAssertEqual(shortModelName("weird-model"), "weird-model")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ModelInfoTests 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'lastModelID' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// The model id of the LAST assistant entry in a transcript (#105) —
/// the model the session is currently running. Same defensive reverse
/// scan as `contextFraction` (#96); nil when no assistant entry carries
/// a model.
public func lastModelID(transcriptJSONL: String) -> String? {
    let lines = transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true)
    for line in lines.reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { continue }
        let isAssistant = (obj["type"] as? String) == "assistant"
            || (message["role"] as? String) == "assistant"
        guard isAssistant, let model = message["model"] as? String, !model.isEmpty else { continue }
        return model
    }
    return nil
}

/// "claude-haiku-4-5-20251001" → "haiku-4.5"; "claude-fable-5" → "fable-5".
/// Strip the vendor prefix and date suffix, then join a trailing pair of
/// numeric segments with a dot. Unknown shapes pass through untouched.
public func shortModelName(_ raw: String) -> String {
    var name = raw.hasPrefix("claude-") ? String(raw.dropFirst("claude-".count)) : raw
    var parts = name.split(separator: "-").map(String.init)
    if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
        parts.removeLast()   // date suffix like 20251001
    }
    if parts.count >= 3,
       parts[parts.count - 1].allSatisfy(\.isNumber),
       parts[parts.count - 2].allSatisfy(\.isNumber) {
        let minor = parts.removeLast()
        parts[parts.count - 1] += ".\(minor)"
    }
    name = parts.joined(separator: "-")
    return name.isEmpty ? raw : name
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ModelInfoTests 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/ModelInfo.swift Tests/ClaudeLightCoreTests/ModelInfoTests.swift
git commit -m "feat: last-model extraction and short model names (#105)"
```

---

### Task 2: `model` on Session + ApplyHook wiring

**Files:**
- Modify: `Sources/ClaudeLightCore/Session.swift` (property after `branch`, init param after `branch: String? = nil`, CodingKeys `case model`)
- Modify: `Sources/ClaudeLightCore/ApplyHook.swift` (Session construction)
- Test: `Tests/ClaudeLightCoreTests/SessionTests.swift`, `Tests/ClaudeLightCoreTests/ApplyHookTests.swift` (append)

**Interfaces:**
- Consumes: `lastModelID(transcriptJSONL:)` (Task 1).
- Produces: `Session.model: String?` (JSON key `model`), populated by `applyHook`.

- [ ] **Step 1: Write the failing tests**

Append to `SessionTests.swift`:

```swift
    func test_model_roundTrips_andAbsentKeyDecodes() throws {
        let s = Session(sessionID: "m1", status: .running, project: "p", cwd: "/x",
                        updatedAt: Date(timeIntervalSince1970: 1_719_745_200),
                        model: "claude-fable-5")
        let back = try ClaudeLightJSON.decoder.decode(Session.self,
                                                      from: ClaudeLightJSON.encoder.encode(s))
        XCTAssertEqual(back.model, "claude-fable-5")
        let json = #"{"session_id":"m2","status":"idle","project":"p","cwd":"/x","updated_at":"2026-07-05T08:00:00Z"}"#
        XCTAssertNil(try ClaudeLightJSON.decoder.decode(Session.self, from: Data(json.utf8)).model)
    }
```

Append inside `ApplyHookTests` (the class has `tempStore()` and `now` helpers):

```swift
    // MARK: – Model persistence (#105)

    private let modelEntry = #"{"type":"assistant","message":{"role":"assistant","model":"claude-fable-5","usage":{"input_tokens":10}}}"#

    func test_applyHook_capturesModel_fromTranscript() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil)
        try applyHook(p, to: store, now: now, transcriptJSONL: modelEntry)
        XCTAssertEqual(try store.loadAll().first?.model, "claude-fable-5")
    }

    func test_applyHook_keepsModel_whenNoTranscript() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil),
                      to: store, now: now, transcriptJSONL: modelEntry)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.model, "claude-fable-5")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionTests 2>&1 | tail -5`
Expected: compile FAILURE — `extra argument 'model' in call`.

- [ ] **Step 3: Implement**

`Session.swift` — after the `branch` property:

```swift
    /// Model id of the session's last assistant turn (#105); nil until a
    /// transcript-bearing event, and for sessions written by older hooks.
    public var model: String?
```

Init gains `model: String? = nil` after `branch: String? = nil`, body gains `self.model = model`, CodingKeys gains `case model`.

`ApplyHook.swift` — in the `Session(...)` construction, after the `branch:` argument:

```swift
            // Model refreshes with the same cadence as contextFraction:
            // only a transcript-bearing event re-reads it (#105).
            model: transcriptJSONL.flatMap { lastModelID(transcriptJSONL: $0) }
                ?? existing?.model
```

- [ ] **Step 4: Run the affected filters, then the full suite**

Run: `swift test --filter SessionTests 2>&1 | grep -E "Executed [0-9]+ tests"` then `swift test --filter ApplyHookTests 2>&1 | grep -E "Executed [0-9]+ tests"` then full suite.
Expected: 0 failures everywhere.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/Session.swift Sources/ClaudeLightCore/ApplyHook.swift Tests/ClaudeLightCoreTests/SessionTests.swift Tests/ClaudeLightCoreTests/ApplyHookTests.swift
git commit -m "feat: persist the session's model id (#105)"
```

---

### Task 3: Chip UI on the session card

**Files:**
- Modify: `Sources/ClaudeLightApp/SessionCard.swift` (subtitle block ~lines 69-81; accessibility label array ~line 100)

**Interfaces:**
- Consumes: `Session.model` (Task 2), `shortModelName(_:)` (Task 1).
- Produces: rendered chip; no new public API.

No unit tests — app-target glue; gates are `swift build` + full suite regression + Task 4 live verification.

- [ ] **Step 1: Replace the subtitle block**

```swift
            if let subtitle = cardSubtitle(for: session, errorReason: errorReason) {
                let isBranch = subtitleShowsBranch(for: session)
                HStack(spacing: 8) {
                    Text(subtitle)
                        .font(.system(size: isBranch ? 11 : 12))
                        .foregroundStyle(session.status == .error
                                         ? AnyShapeStyle(PanelPalette.red)
                                         : isBranch
                                         ? AnyShapeStyle(PanelPalette.branchAmber)
                                         : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
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
                }
                .padding(.leading, 18)
            }
```

- [ ] **Step 2: VoiceOver** — in the card's `.accessibilityLabel` array (currently `[ClaudeLightCore.accessibilityLabel(for: session), cardSubtitle(...), session.contextFraction.map { contextTooltip(fraction: $0) }]`), insert after the `cardSubtitle` element:

```swift
                             session.model.map { "model \(shortModelName($0))" },
```

- [ ] **Step 3: Build + full suite**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Build complete!`, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/SessionCard.swift
git commit -m "feat: model chip on session cards (#105)"
```

---

### Task 4: Live verification and PR (controller-run)

- [ ] Build/sign/swap the local app (standard flow; both binaries — the hook writes the new key).
- [ ] Verify live: this session's card shows a `FABLE-5` chip at the subtitle's right edge (after its next transcript-bearing hook event); hover shows the full id; a long branch truncates before the chip moves.
- [ ] Push and open the PR titled "feat: model chip on session cards (#105)" — body: extraction (same tail pass as #96, no new I/O), contextFraction-style merge, chip styling + a11y, test counts, live verification. Closes #105.
