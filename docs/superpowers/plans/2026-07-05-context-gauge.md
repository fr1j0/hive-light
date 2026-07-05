# Context-Usage Gauge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five segment ticks beside each session card's timer showing context-window usage — grey / orange (≥75%) / red (≥90%), exact percentage in a hover tooltip (#96).

**Architecture:** The hook's Stop path already reads the transcript tail; a new pure Core function extracts the last assistant entry's `usage` and computes tokens/window. `applyHook` stores the fraction in the session JSON, merging the previous value on transcript-less events (like terminal identity). `SessionCard` renders a five-tick gauge; all math lives in tested PanelModel helpers.

**Tech Stack:** Swift 5.9 (SwiftPM), XCTest, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-07-05-context-gauge-design.md`

## Global Constraints

- Work on branch `feat/context-gauge` (already created). Never commit to `main`.
- No AI attribution anywhere: no `Co-Authored-By` trailers, no "Generated with" footers.
- Exact values: thresholds `ok < 0.75`, `warm 0.75..<0.9`, `hot >= 0.9`; five ticks, lit = `Int((fraction * 5).rounded(.up))` clamped 1...5; tooltip exactly `"context NN% used"` (whole-number percent); JSON key `context_fraction`; windows 200_000 default, 1_000_000 when the lowercased model id contains `"[1m]"` or `"-1m"`.
- Context tokens = `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`, missing keys count 0; fraction clamped at 1.0; nil when no assistant usage entry parses.
- The fraction PERSISTS across transcript-less hook events (merge `existing?.contextFraction`) — unlike `detail`, which clears by design.
- No new transcript reads: extraction runs only where `transcriptJSONL` is already provided (the Stop path). No notification/light/sort changes.
- `swift test` zero failures and `swift build` success before each commit.

---

### Task 1: Core extraction + gauge math

**Files:**
- Create: `Sources/ClaudeLightCore/ContextUsage.swift`
- Modify: `Sources/ClaudeLightCore/PanelModel.swift` (append helpers)
- Test: `Tests/ClaudeLightCoreTests/ContextUsageTests.swift` (new), `Tests/ClaudeLightCoreTests/PanelModelTests.swift` (append)

**Interfaces:**
- Produces: `public func contextFraction(transcriptJSONL: String) -> Double?`; `public enum ContextLevel: Equatable, Sendable { case ok, warm, hot }`; `public func contextLevel(fraction: Double) -> ContextLevel`; `public func contextSegments(fraction: Double) -> Int`; `public func contextTooltip(fraction: Double) -> String`. Tasks 2–3 consume these exactly.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeLightCoreTests/ContextUsageTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class ContextUsageTests: XCTestCase {
    private func assistantUsage(input: Int, cacheRead: Int = 0, cacheCreation: Int = 0,
                                model: String = "claude-sonnet-5") -> String {
        #"{"type":"assistant","message":{"role":"assistant","model":"\#(model)","usage":{"input_tokens":\#(input),"cache_read_input_tokens":\#(cacheRead),"cache_creation_input_tokens":\#(cacheCreation)},"content":[{"type":"text","text":"x"}]}}"#
    }
    private func assistantInputOnly(input: Int) -> String {
        #"{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-5","usage":{"input_tokens":\#(input)},"content":[{"type":"text","text":"x"}]}}"#
    }
    private func assistantTextNoUsage() -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"no usage here"}]}}"#
    }

    func test_sumsAllThreeTokenFields() {
        let t = assistantUsage(input: 10_000, cacheRead: 80_000, cacheCreation: 10_000)
        XCTAssertEqual(contextFraction(transcriptJSONL: t)!, 0.5, accuracy: 0.0001)
    }

    func test_missingCacheFields_countZero() {
        XCTAssertEqual(contextFraction(transcriptJSONL: assistantInputOnly(input: 50_000))!,
                       0.25, accuracy: 0.0001)
    }

    func test_lastUsageEntryWins() {
        let t = [assistantUsage(input: 20_000),
                 assistantUsage(input: 150_000)].joined(separator: "\n")
        XCTAssertEqual(contextFraction(transcriptJSONL: t)!, 0.75, accuracy: 0.0001)
    }

    func test_trailingEntriesWithoutUsage_areSkipped() {
        let t = [assistantUsage(input: 100_000),
                 assistantTextNoUsage(),
                 "not json at all"].joined(separator: "\n")
        XCTAssertEqual(contextFraction(transcriptJSONL: t)!, 0.5, accuracy: 0.0001)
    }

    func test_noUsageAnywhere_returnsNil() {
        XCTAssertNil(contextFraction(transcriptJSONL: ""))
        XCTAssertNil(contextFraction(transcriptJSONL: assistantTextNoUsage()))
    }

    func test_oneMillionWindow_modelMarker() {
        let t = assistantUsage(input: 500_000, model: "claude-sonnet-4-5[1m]")
        XCTAssertEqual(contextFraction(transcriptJSONL: t)!, 0.5, accuracy: 0.0001)
    }

    func test_clampedAtOne() {
        XCTAssertEqual(contextFraction(transcriptJSONL: assistantUsage(input: 300_000))!,
                       1.0, accuracy: 0.0001)
    }
}
```

Append to `Tests/ClaudeLightCoreTests/PanelModelTests.swift`:

```swift
    func test_contextSegments_boundaries() {
        XCTAssertEqual(contextSegments(fraction: 0.01), 1)
        XCTAssertEqual(contextSegments(fraction: 0.46), 3)
        XCTAssertEqual(contextSegments(fraction: 0.75), 4)
        XCTAssertEqual(contextSegments(fraction: 0.9), 5)
        XCTAssertEqual(contextSegments(fraction: 1.0), 5)
    }

    func test_contextLevel_thresholds() {
        XCTAssertEqual(contextLevel(fraction: 0.74), .ok)
        XCTAssertEqual(contextLevel(fraction: 0.75), .warm)
        XCTAssertEqual(contextLevel(fraction: 0.89), .warm)
        XCTAssertEqual(contextLevel(fraction: 0.9), .hot)
    }

    func test_contextTooltip_wording() {
        XCTAssertEqual(contextTooltip(fraction: 0.78), "context 78% used")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'contextFraction' in scope` (etc.).

- [ ] **Step 3: Implement**

Create `Sources/ClaudeLightCore/ContextUsage.swift`:

```swift
import Foundation

/// Best-effort context-window usage from a Claude Code transcript (JSONL).
/// The LAST assistant entry carrying `message.usage` reflects the prompt
/// size of the latest API call — i.e. the session's current context
/// footprint (#96). Returns tokens/window clamped to 1.0, or nil when no
/// usage entry parses. Format is undocumented; defensive and fail-safe.
public func contextFraction(transcriptJSONL: String) -> Double? {
    let lines = transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true)
    for line in lines.reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { continue }
        let isAssistant = (obj["type"] as? String) == "assistant"
            || (message["role"] as? String) == "assistant"
        guard isAssistant, let usage = message["usage"] as? [String: Any] else { continue }
        func tokens(_ key: String) -> Double {
            (usage[key] as? NSNumber)?.doubleValue ?? 0
        }
        let total = tokens("input_tokens") + tokens("cache_read_input_tokens")
                  + tokens("cache_creation_input_tokens")
        guard total > 0 else { continue }
        return min(total / contextWindow(forModel: message["model"] as? String), 1.0)
    }
    return nil
}

/// The model's context window in tokens. 1M-context model ids carry a
/// "[1m]" / "-1m" marker; everything else defaults to the standard 200k,
/// so unknown models read slightly hot rather than slightly safe.
func contextWindow(forModel model: String?) -> Double {
    guard let model = model?.lowercased() else { return 200_000 }
    if model.contains("[1m]") || model.contains("-1m") { return 1_000_000 }
    return 200_000
}
```

Append to `Sources/ClaudeLightCore/PanelModel.swift`:

```swift
/// Urgency bands for the context gauge (#96).
public enum ContextLevel: Equatable, Sendable {
    case ok      // < 0.75
    case warm    // 0.75 ..< 0.9 — auto-compact approaching
    case hot     // >= 0.9
}

public func contextLevel(fraction: Double) -> ContextLevel {
    if fraction >= 0.9 { return .hot }
    if fraction >= 0.75 { return .warm }
    return .ok
}

/// Lit ticks out of 5 — any measured usage lights at least one.
public func contextSegments(fraction: Double) -> Int {
    min(max(Int((fraction * 5).rounded(.up)), 1), 5)
}

/// Hover tooltip for the tick group — the one place the exact number lives.
public func contextTooltip(fraction: Double) -> String {
    "context \(Int((fraction * 100).rounded()))% used"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"`
Expected: all pass (count grows by 10).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/ContextUsage.swift Sources/ClaudeLightCore/PanelModel.swift Tests/
git commit -m "feat: context-usage extraction and gauge math (#96)"
```

---

### Task 2: Schema + applyHook persistence

**Files:**
- Modify: `Sources/ClaudeLightCore/Session.swift` (property, init, CodingKeys)
- Modify: `Sources/ClaudeLightCore/ApplyHook.swift` (the `Session(...)` construction)
- Test: `Tests/ClaudeLightCoreTests/ApplyHookTests.swift` (append)

**Interfaces:**
- Consumes: `contextFraction(transcriptJSONL:)` (Task 1).
- Produces: `Session.contextFraction: Double?` (JSON key `context_fraction`, LAST init parameter, default nil). Task 3 reads it.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeLightCoreTests/ApplyHookTests.swift` (reuse the class's `tempStore()`/`now` helpers):

```swift
    private let usageTranscript =
        #"{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-5","usage":{"input_tokens":100000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"x"}]}}"#

    func test_stopWithTranscript_writesContextFraction() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil),
                      to: store, now: now, transcriptJSONL: usageTranscript)
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(try XCTUnwrap(s.contextFraction), 0.5, accuracy: 0.0001)
    }

    func test_transcriptlessEvent_preservesContextFraction() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil),
                      to: store, now: now, transcriptJSONL: usageTranscript)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now.addingTimeInterval(1))
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(s.status, .running)
        XCTAssertEqual(try XCTUnwrap(s.contextFraction), 0.5, accuracy: 0.0001)
    }

    func test_freshSessionWithoutTranscript_nilFraction() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now)
        XCTAssertNil(try store.loadAll().first?.contextFraction)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: compile FAILURE — `value of type 'Session' has no member 'contextFraction'`.

- [ ] **Step 3: Implement**

`Sources/ClaudeLightCore/Session.swift` — add after `detail`:

```swift
    /// Context-window usage 0...1 measured at the last Stop (#96): the last
    /// assistant entry's usage tokens over the model's window. Persists
    /// across transcript-less events; nil until first measured.
    public var contextFraction: Double?
```

add `contextFraction: Double? = nil` as the LAST init parameter (with `self.contextFraction = contextFraction`), and add `case contextFraction = "context_fraction"` to CodingKeys.

`Sources/ClaudeLightCore/ApplyHook.swift` — in the `Session(...)` construction, after the `detail:` argument add:

```swift
            // Context usage refreshes only when a transcript is in hand (the
            // Stop path); other events keep the last measurement (#96).
            contextFraction: transcriptJSONL.flatMap { contextFraction(transcriptJSONL: $0) }
                ?? existing?.contextFraction
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with" && swift build 2>&1 | tail -1`
Expected: all pass (count grows by 3), `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/Session.swift Sources/ClaudeLightCore/ApplyHook.swift Tests/
git commit -m "feat: persist context fraction in the session file (#96)"
```

---

### Task 3: `ContextTicks` view on the card

**Files:**
- Modify: `Sources/ClaudeLightApp/SessionCard.swift` (title-row HStack + new view)

**Interfaces:**
- Consumes: `session.contextFraction` (Task 2); `contextSegments`/`contextLevel`/`contextTooltip` (Task 1); `PanelPalette` (existing).

- [ ] **Step 1: Implement**

In `Sources/ClaudeLightApp/SessionCard.swift`, the card's title row currently reads:

```swift
                Spacer(minLength: 8)
                Text(timerText(for: session, now: now))
```

Change to:

```swift
                Spacer(minLength: 8)
                if let fraction = session.contextFraction {
                    ContextTicks(fraction: fraction)
                }
                Text(timerText(for: session, now: now))
```

Append at the end of the file:

```swift
/// Five-tick context gauge (#96): lit count = usage, color = urgency.
/// The exact percentage lives only in the tooltip.
struct ContextTicks: View {
    let fraction: Double

    var body: some View {
        let lit = contextSegments(fraction: fraction)
        let color = Self.color(for: contextLevel(fraction: fraction))
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < lit ? color : Color.primary.opacity(0.15))
                    .frame(width: 4, height: 7)
            }
        }
        .help(contextTooltip(fraction: fraction))
        .accessibilityLabel(contextTooltip(fraction: fraction))
    }

    private static func color(for level: ContextLevel) -> Color {
        switch level {
        case .ok: return Color.secondary
        case .warm: return PanelPalette.orange
        case .hot: return PanelPalette.red
        }
    }
}
```

- [ ] **Step 2: Build and run the suite**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"`
Expected: `Build complete!`, all tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/SessionCard.swift
git commit -m "feat: context ticks on session cards (#96)"
```

---

### Task 4: End-to-end verification

**Files:** none (verification only)

**Interfaces:**
- Consumes: the complete branch (Tasks 1–3).

- [ ] **Step 1: Launch the debug build**

```bash
swift build 2>&1 | tail -1
(.build/debug/ClaudeLightApp >/dev/null 2>&1 &)
```

- [ ] **Step 2: Stage all three levels with fake sessions**

```bash
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for spec in "ctx-ok:0.46" "ctx-warm:0.78" "ctx-hot:0.93"; do
  name="${spec%%:*}"; frac="${spec##*:}"
  cat > ~/.claude-light/sessions/$name.json <<EOF
{"cwd":"/tmp/$name","status":"running","updated_at":"$NOW","session_id":"$name","project":"$name","tty":"ttys98${name: -1}","context_fraction":$frac}
EOF
done
```

Verify in the debug panel (user check): `ctx-ok` shows 3 grey ticks, `ctx-warm` 4 orange, `ctx-hot` 5 red; hovering shows "context 78% used" etc.; the live session shows ticks only after its next Stop event (real extraction).

- [ ] **Step 3: Verify real extraction against the live transcript**

```bash
echo "{\"session_id\":\"ctx-real-e2e\",\"hook_event_name\":\"Stop\",\"cwd\":\"/tmp/x\",\"transcript_path\":\"$(ls ~/.claude/projects/-Users-fernandocastillo-Projects-claude-light/*.jsonl | head -1)\"}" | .build/debug/claude-light-hook
python3 -c "import json,glob; print(json.load(open(glob.glob('$HOME/.claude-light/sessions/ctx-real-e2e.json')[0])).get('context_fraction'))"
```

Expected: a plausible fraction (0 < f ≤ 1) extracted from a real transcript.

- [ ] **Step 4: Clean up**

```bash
pkill -f "debug/ClaudeLightApp"
rm -f ~/.claude-light/sessions/ctx-*.json
```

Record observations; no commit.

---

## After all tasks

Push and open the PR: title `feat: context-usage gauge on session cards`, `Closes #96`.
