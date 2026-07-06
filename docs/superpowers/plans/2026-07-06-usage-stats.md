# Usage Stats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A toggleable usage glance — per-model token burn in the current 5h window with reset countdown (micro-bar row above the footer) — plus a dedicated Usage view with real fetched plan-limit bars (opt-in) and daily history.

**Architecture:** Pure logic in `ClaudeLightCore` (window tiling, entry parsing, aggregation, cache decoding, formatting, color slots — all tested). The app adds a `UsageScanner` that scans recently-modified transcripts **off the main actor** (memoized via `FileMemoCache`), a `UsageRow` docked at the panel's reserved #83 slot, a `UsageView` pane on the existing flip mechanism, and one Settings toggle.

**Tech Stack:** Swift 5.9 / SwiftUI, XCTest, SPM (`swift test`), macOS 13 floor.

## Global Constraints

- Token basis everywhere: `input_tokens + output_tokens` — cache read/creation tokens are **excluded** (matches `stats-cache.json`'s daily basis).
- The transcript scan must NEVER run synchronously on the main actor (the archived quota-window attempt's unresolved Critical). Pattern: `@MainActor` class starts a `Task.detached` for the work, publishes back on main.
- Model palette (validated categorical, fixed per family, never cycled): Fable `#3987e5`, Opus `#199e70`, Sonnet `#c98500`, Haiku `#9085e9`, other → `Color.primary.opacity(0.35)`. Red/orange/green are reserved for session status — never use them for models.
- No percentages of quota anywhere; bars are relative to each other, never to a cap.
- Settings toggle `Show usage stats` defaults **off** (`UserDefaults.standard.bool` default false, like `showSubagents`).
- SF Symbol for reset: `arrow.clockwise` (macOS 13-safe). No raw glyph characters (the `⑂` lesson).
- Panel rhythm: 12pt frame, 10pt stack spacing, 22pt content column, dividers to the 12pt edge.
- CI strict concurrency: never capture mutable `self` in a detached task — bind what you need first (release-ci-strict-concurrency).
- Fail-safe parsing: unparseable JSONL lines/files are skipped, never crash; transcript tails are decoded lossy (`String(decoding:as:)`), never strict UTF-8 (#111).
- Plan limits fetch: `GET https://api.anthropic.com/api/oauth/usage`, headers `Authorization: Bearer <token>` + `anthropic-beta: oauth-2025-04-20`; token from Keychain generic password, service `"Claude Code-credentials"`, JSON key `claudeAiOauth.accessToken`. Decode ONLY the response's `limits[]` array. Verified live 2026-07-06 (HTTP 200).
- The token must NEVER be logged, printed, persisted, or sent anywhere except the Authorization header of that one request. Fetch failures of any kind → empty limits, silently — never an error state.
- Fetch runs only when the `Show plan limits` toggle is on AND the panel is open; min 5 minutes between fetches. Both usage toggles default off.
- Plan-limit bars use urgency colors (`ContextLevel` mapping: <75% primary, 75–90% orange, ≥90% red), NOT model categorical colors — they are capacity, not identity.
- No AI attribution in commits.

---

### Task 1: Core — usage entries & 5h window math

**Files:**
- Create: `Sources/ClaudeLightCore/UsageWindow.swift`
- Test: `Tests/ClaudeLightCoreTests/UsageWindowTests.swift`

**Interfaces:**
- Consumes: nothing new (mirrors `ContextUsage.swift` parsing idioms).
- Produces (later tasks rely on these exact signatures):
  - `public struct UsageEntry: Equatable, Sendable { let timestamp: Date; let model: String; let tokens: Int }`
  - `public func usageEntries(transcriptJSONL: String) -> [UsageEntry]`
  - `public func currentUsageWindow(now: Date, timestamps: [Date], windowLength: TimeInterval = 5*3600) -> (start: Date, end: Date)?`
  - `public struct ModelBurn: Equatable, Sendable { let model: String; let tokens: Int }`
  - `public func usageByModel(_ entries: [UsageEntry], from start: Date, to end: Date) -> [ModelBurn]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeLightCoreTests/UsageWindowTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class UsageWindowTests: XCTestCase {
    // MARK: fixtures

    private func iso(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }

    /// One transcript line the way Claude Code writes assistant entries.
    private func entry(_ ts: String, model: String, id: String? = nil,
                       input: Int, output: Int, cacheRead: Int = 0) -> String {
        let idPart = id.map { #""id":"\#($0)","# } ?? ""
        return #"{"type":"assistant","timestamp":"\#(ts)","message":{\#(idPart)"role":"assistant","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_read_input_tokens":\#(cacheRead)}}}"#
    }
    private func join(_ lines: [String]) -> String { lines.joined(separator: "\n") }

    // MARK: usageEntries

    func test_usageEntries_parsesAssistantUsage_excludingCacheTokens() {
        let t = entry("2026-07-06T10:00:00Z", model: "claude-fable-5",
                      input: 1_000, output: 2_000, cacheRead: 9_000_000)
        let entries = usageEntries(transcriptJSONL: t)
        XCTAssertEqual(entries, [UsageEntry(timestamp: iso("2026-07-06T10:00:00Z"),
                                            model: "claude-fable-5", tokens: 3_000)])
    }

    func test_usageEntries_dedupesStreamingByMessageID_lastWins() {
        // Streaming writes several lines per assistant message with cumulative
        // usage under the same message id — only the last occurrence counts.
        let t = join([
            entry("2026-07-06T10:00:00Z", model: "claude-fable-5", id: "m1", input: 100, output: 50),
            entry("2026-07-06T10:00:05Z", model: "claude-fable-5", id: "m1", input: 100, output: 900),
            entry("2026-07-06T10:01:00Z", model: "claude-fable-5", id: "m2", input: 10, output: 10),
        ])
        let entries = usageEntries(transcriptJSONL: t)
        XCTAssertEqual(entries.map(\.tokens), [1_000, 20])
    }

    func test_usageEntries_skipsGarbageUserAndZeroUsage() {
        let user = #"{"type":"user","timestamp":"2026-07-06T10:00:00Z","message":{"role":"user","content":"hi"}}"#
        let zero = entry("2026-07-06T10:00:01Z", model: "claude-fable-5", input: 0, output: 0)
        let t = join(["not json", user, zero])
        XCTAssertTrue(usageEntries(transcriptJSONL: t).isEmpty)
    }

    func test_usageEntries_fractionalSecondTimestamps_parse() {
        let t = #"{"type":"assistant","timestamp":"2026-07-06T10:00:00.123Z","message":{"role":"assistant","model":"claude-sonnet-5","usage":{"input_tokens":5,"output_tokens":5}}}"#
        XCTAssertEqual(usageEntries(transcriptJSONL: t).count, 1)
    }

    // MARK: currentUsageWindow

    func test_window_singleBurst_startsAtFirstActivity() {
        let t0 = iso("2026-07-06T09:00:00Z")
        let now = iso("2026-07-06T10:00:00Z")
        let w = currentUsageWindow(now: now, timestamps: [t0, iso("2026-07-06T09:30:00Z")])
        XCTAssertEqual(w?.start, t0)
        XCTAssertEqual(w?.end, t0.addingTimeInterval(5 * 3600))
    }

    func test_window_gapOfFiveHours_opensFreshWindow() {
        let old = iso("2026-07-06T00:00:00Z")
        let fresh = iso("2026-07-06T06:00:00Z")   // 6h after old
        let now = iso("2026-07-06T07:00:00Z")
        let w = currentUsageWindow(now: now, timestamps: [old, fresh])
        XCTAssertEqual(w?.start, fresh)
    }

    func test_window_continuousActivity_chainsTiling() {
        // Activity every hour from 00:00; at 06:30 the current window is the
        // second tile, opening at the first activity ≥ 05:00.
        let times = (0...6).map { iso(String(format: "2026-07-06T%02d:00:00Z", $0)) }
        let now = iso("2026-07-06T06:30:00Z")
        let w = currentUsageWindow(now: now, timestamps: times)
        XCTAssertEqual(w?.start, iso("2026-07-06T05:00:00Z"))
        XCTAssertEqual(w?.end, iso("2026-07-06T10:00:00Z"))
    }

    func test_window_lastWindowClosed_returnsNil() {
        let t0 = iso("2026-07-06T00:00:00Z")
        let now = iso("2026-07-06T06:00:00Z")   // window [00:00,05:00) closed, nothing since
        XCTAssertNil(currentUsageWindow(now: now, timestamps: [t0]))
    }

    func test_window_noTimestamps_returnsNil() {
        XCTAssertNil(currentUsageWindow(now: Date(), timestamps: []))
    }

    // MARK: usageByModel

    func test_usageByModel_sumsFiltersAndSortsDescending() {
        let start = iso("2026-07-06T10:00:00Z"), end = iso("2026-07-06T15:00:00Z")
        let entries = [
            UsageEntry(timestamp: iso("2026-07-06T09:59:59Z"), model: "claude-fable-5", tokens: 999),   // before window
            UsageEntry(timestamp: iso("2026-07-06T10:30:00Z"), model: "claude-fable-5", tokens: 700),
            UsageEntry(timestamp: iso("2026-07-06T11:00:00Z"), model: "claude-sonnet-5", tokens: 900),
            UsageEntry(timestamp: iso("2026-07-06T12:00:00Z"), model: "claude-fable-5", tokens: 300),
            UsageEntry(timestamp: iso("2026-07-06T15:00:00Z"), model: "claude-haiku-4-5", tokens: 50),  // at end → excluded
        ]
        let burn = usageByModel(entries, from: start, to: end)
        XCTAssertEqual(burn, [ModelBurn(model: "claude-fable-5", tokens: 1_000),
                              ModelBurn(model: "claude-sonnet-5", tokens: 900)])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter UsageWindowTests`
Expected: FAIL — `usageEntries`, `currentUsageWindow`, `UsageEntry`, `ModelBurn` undefined.

- [ ] **Step 3: Implement**

Create `Sources/ClaudeLightCore/UsageWindow.swift`:

```swift
import Foundation

/// One assistant turn's token spend: when, which model, in+out tokens.
/// Cache read/creation tokens are deliberately excluded — this matches the
/// basis Claude Code's own stats cache uses, so live and historical numbers
/// agree (#83).
public struct UsageEntry: Equatable, Sendable {
    public let timestamp: Date
    public let model: String
    public let tokens: Int

    public init(timestamp: Date, model: String, tokens: Int) {
        self.timestamp = timestamp
        self.model = model
        self.tokens = tokens
    }
}

/// A model's summed burn over some range, for display.
public struct ModelBurn: Equatable, Sendable {
    public let model: String
    public let tokens: Int

    public init(model: String, tokens: Int) {
        self.model = model
        self.tokens = tokens
    }
}

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain = ISO8601DateFormatter()

private func parseTimestamp(_ s: String) -> Date? {
    isoFractional.date(from: s) ?? isoPlain.date(from: s)
}

/// Per-entry token spend from a transcript (JSONL). Streaming writes several
/// lines per assistant message with cumulative usage under one message id —
/// dedupe by id, last occurrence wins. Same defensive scan idiom as
/// `contextFraction` (#96): unparseable lines are skipped, never crash.
public func usageEntries(transcriptJSONL: String) -> [UsageEntry] {
    var byID: [String: UsageEntry] = [:]
    var anonymous: [UsageEntry] = []
    for line in transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { continue }
        let isAssistant = (obj["type"] as? String) == "assistant"
            || (message["role"] as? String) == "assistant"
        guard isAssistant,
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, !model.isEmpty,
              let ts = obj["timestamp"] as? String,
              let date = parseTimestamp(ts) else { continue }
        let tokens = ((usage["input_tokens"] as? NSNumber)?.intValue ?? 0)
                   + ((usage["output_tokens"] as? NSNumber)?.intValue ?? 0)
        guard tokens > 0 else { continue }
        let entry = UsageEntry(timestamp: date, model: model, tokens: tokens)
        if let id = message["id"] as? String {
            byID[id] = entry   // streaming: last occurrence carries final counts
        } else {
            anonymous.append(entry)
        }
    }
    return (Array(byID.values) + anonymous).sorted { $0.timestamp < $1.timestamp }
}

/// Gap-aware 5h tiling (#83): a window opens at the first activity after the
/// previous window closes. Anchored at the first activity after the last
/// ≥`windowLength` idle gap — any window containing the gap's earlier side has
/// closed before its later side, so the later side opens fresh. Returns the
/// window containing `now`, or nil when the last window has already closed.
public func currentUsageWindow(now: Date, timestamps: [Date],
                               windowLength: TimeInterval = 5 * 3600) -> (start: Date, end: Date)? {
    let past = timestamps.filter { $0 <= now }.sorted()
    guard var start = past.first else { return nil }
    for i in 1..<max(past.count, 1) where past[i].timeIntervalSince(past[i - 1]) >= windowLength {
        start = past[i]
    }
    while now >= start.addingTimeInterval(windowLength) {
        let close = start.addingTimeInterval(windowLength)
        guard let next = past.first(where: { $0 >= close }) else { return nil }
        start = next
    }
    return (start, start.addingTimeInterval(windowLength))
}

/// Per-model sums over [start, end), largest burn first (ties by name for
/// deterministic display).
public func usageByModel(_ entries: [UsageEntry], from start: Date, to end: Date) -> [ModelBurn] {
    var sums: [String: Int] = [:]
    for e in entries where e.timestamp >= start && e.timestamp < end {
        sums[e.model, default: 0] += e.tokens
    }
    return sums.map { ModelBurn(model: $0.key, tokens: $0.value) }
        .sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.model < $1.model }
}
```

Note: `for i in 1..<max(past.count, 1)` — with a single timestamp the range is empty; `max` guards the `1..<1` edge without a branch.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter UsageWindowTests`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/UsageWindow.swift Tests/ClaudeLightCoreTests/UsageWindowTests.swift
git commit -m "feat: usage entries, 5h window tiling, per-model aggregation"
```

---

### Task 2: Core — stats-cache decoding

**Files:**
- Create: `Sources/ClaudeLightCore/StatsCache.swift`
- Test: `Tests/ClaudeLightCoreTests/StatsCacheTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct DailyModelTokens: Equatable, Sendable { let date: String; let tokensByModel: [String: Int] }`
  - `public func dailyModelTokens(fromJSON data: Data) -> [DailyModelTokens]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeLightCoreTests/StatsCacheTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class StatsCacheTests: XCTestCase {
    func test_decodesRealShape() {
        let json = """
        {"version":4,"lastComputedDate":"2026-07-05",
         "dailyModelTokens":[
           {"date":"2026-07-04","tokensByModel":{"claude-fable-5":800000,"claude-sonnet-5":700000}},
           {"date":"2026-07-05","tokensByModel":{"claude-fable-5":1700000}}
         ]}
        """.data(using: .utf8)!
        let rows = dailyModelTokens(fromJSON: json)
        XCTAssertEqual(rows, [
            DailyModelTokens(date: "2026-07-04",
                             tokensByModel: ["claude-fable-5": 800_000, "claude-sonnet-5": 700_000]),
            DailyModelTokens(date: "2026-07-05", tokensByModel: ["claude-fable-5": 1_700_000]),
        ])
    }

    func test_malformedRow_isSkipped_notFatal() {
        let json = """
        {"dailyModelTokens":[
           {"date":"2026-07-04"},
           {"date":"2026-07-05","tokensByModel":{"claude-fable-5":100,"weird":"not a number"}}
         ]}
        """.data(using: .utf8)!
        let rows = dailyModelTokens(fromJSON: json)
        XCTAssertEqual(rows, [DailyModelTokens(date: "2026-07-05",
                                               tokensByModel: ["claude-fable-5": 100])])
    }

    func test_truncatedJSON_returnsEmpty() {
        let json = Data(#"{"dailyModelTokens":[{"date":"2026-0"#.utf8)
        XCTAssertTrue(dailyModelTokens(fromJSON: json).isEmpty)
    }

    func test_missingKey_returnsEmpty() {
        let json = Data(#"{"version":4}"#.utf8)
        XCTAssertTrue(dailyModelTokens(fromJSON: json).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter StatsCacheTests`
Expected: FAIL — `dailyModelTokens` / `DailyModelTokens` undefined.

- [ ] **Step 3: Implement**

Create `Sources/ClaudeLightCore/StatsCache.swift`:

```swift
import Foundation

/// One day's per-model token totals from Claude Code's own stats cache
/// (`~/.claude/stats-cache.json`, `dailyModelTokens`). The cache is computed
/// by Claude Code on its own cadence and typically lags today — the live
/// scanner supplies today's row (#83).
public struct DailyModelTokens: Equatable, Sendable {
    public let date: String              // "2026-07-05", as written by Claude Code
    public let tokensByModel: [String: Int]

    public init(date: String, tokensByModel: [String: Int]) {
        self.date = date
        self.tokensByModel = tokensByModel
    }
}

/// Tolerant decode: the file belongs to another program, so any surprise —
/// truncation, missing keys, non-numeric values, a future schema — degrades
/// to fewer rows or `[]`, never an error.
public func dailyModelTokens(fromJSON data: Data) -> [DailyModelTokens] {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = obj["dailyModelTokens"] as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
        guard let date = row["date"] as? String,
              let raw = row["tokensByModel"] as? [String: Any] else { return nil }
        var tokens: [String: Int] = [:]
        for (model, value) in raw {
            if let n = value as? NSNumber { tokens[model] = n.intValue }
        }
        return DailyModelTokens(date: date, tokensByModel: tokens)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter StatsCacheTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/StatsCache.swift Tests/ClaudeLightCoreTests/StatsCacheTests.swift
git commit -m "feat: tolerant stats-cache dailyModelTokens decoding"
```

---

### Task 3: Core — formatting & model color slots

**Files:**
- Create: `Sources/ClaudeLightCore/UsageFormatting.swift`
- Test: `Tests/ClaudeLightCoreTests/UsageFormattingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public func tokenText(_ tokens: Int) -> String`
  - `public func resetText(until end: Date, now: Date) -> String`
  - `public enum ModelColorSlot: Equatable, Sendable { case fable, opus, sonnet, haiku, other }`
  - `public func modelColorSlot(_ modelID: String) -> ModelColorSlot`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeLightCoreTests/UsageFormattingTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class UsageFormattingTests: XCTestCase {
    func test_tokenText_bands() {
        XCTAssertEqual(tokenText(1_400_000), "1.4M")
        XCTAssertEqual(tokenText(2_000_000), "2.0M")
        XCTAssertEqual(tokenText(320_000), "320k")
        XCTAssertEqual(tokenText(999_999), "1000k")   // documents the band edge
        XCTAssertEqual(tokenText(980), "980")
        XCTAssertEqual(tokenText(0), "0")
    }

    func test_resetText_bands() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(resetText(until: now.addingTimeInterval(6_000), now: now), "1h 40m")
        XCTAssertEqual(resetText(until: now.addingTimeInterval(3_600), now: now), "1h 0m")
        XCTAssertEqual(resetText(until: now.addingTimeInterval(2_400), now: now), "40m")
        XCTAssertEqual(resetText(until: now.addingTimeInterval(30), now: now), "<1m")
    }

    func test_modelColorSlot_datedAndBareIDs() {
        XCTAssertEqual(modelColorSlot("claude-fable-5"), .fable)
        XCTAssertEqual(modelColorSlot("claude-opus-4-8"), .opus)
        XCTAssertEqual(modelColorSlot("claude-sonnet-5"), .sonnet)
        XCTAssertEqual(modelColorSlot("claude-haiku-4-5-20251001"), .haiku)
        XCTAssertEqual(modelColorSlot("some-future-model"), .other)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter UsageFormattingTests`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement**

Create `Sources/ClaudeLightCore/UsageFormatting.swift`:

```swift
import Foundation

/// "1.4M" / "320k" / "980" — one decimal at M scale, none below.
public func tokenText(_ tokens: Int) -> String {
    if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
    if tokens >= 1_000 { return "\(Int((Double(tokens) / 1_000).rounded()))k" }
    return "\(tokens)"
}

/// Countdown to the window close: "1h 40m" / "40m" / "<1m".
public func resetText(until end: Date, now: Date) -> String {
    let remaining = end.timeIntervalSince(now)
    guard remaining >= 60 else { return "<1m" }
    let h = Int(remaining) / 3600
    let m = (Int(remaining) % 3600) / 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

/// Fixed categorical slot per model family (#83) — the palette is assigned
/// by entity and never cycled. Substring family match, like `shortModelName`,
/// so dated and bare ids both resolve.
public enum ModelColorSlot: Equatable, Sendable { case fable, opus, sonnet, haiku, other }

public func modelColorSlot(_ modelID: String) -> ModelColorSlot {
    let m = modelID.lowercased()
    if m.contains("fable") { return .fable }
    if m.contains("opus") { return .opus }
    if m.contains("sonnet") { return .sonnet }
    if m.contains("haiku") { return .haiku }
    return .other
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter UsageFormattingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/UsageFormatting.swift Tests/ClaudeLightCoreTests/UsageFormattingTests.swift
git commit -m "feat: usage formatting and model color slots"
```

---

### Task 4: App — UsageScanner (off-main transcript scan) + settings flag

**Files:**
- Create: `Sources/ClaudeLightApp/UsageScanner.swift`
- Modify: `Sources/ClaudeLightApp/SessionWatcher.swift` (add `showUsageStats`, mirroring `showSubagents` at lines 21-23, 41, 59)

**Interfaces:**
- Consumes: `usageEntries`, `currentUsageWindow`, `usageByModel`, `ModelBurn`, `dailyModelTokens`, `DailyModelTokens`, `FileMemoCache`, `FileStamp` (Tasks 1-2 + existing Core).
- Produces:
  - `struct UsageSnapshot: Equatable { var windowBurn: [ModelBurn]; var windowEnd: Date?; var todayBurn: [ModelBurn]; var dailyHistory: [DailyModelTokens] }`
  - `@MainActor final class UsageScanner: ObservableObject` with `@Published private(set) var snapshot: UsageSnapshot` and `func refresh(force: Bool = false)`
  - `SessionWatcher.showUsageStats: Bool` (`@Published`, UserDefaults-persisted, key `"showUsageStats"`)

This task is app plumbing over already-tested Core functions — no new unit tests; verify by build + full suite.

- [ ] **Step 1: Add the settings flag to SessionWatcher**

In `Sources/ClaudeLightApp/SessionWatcher.swift`, next to the existing `showSubagents` property (line 21):

```swift
    @Published var showUsageStats: Bool {
        didSet {
            UserDefaults.standard.set(showUsageStats, forKey: Self.showUsageStatsKey)
        }
    }
```

Next to `showSubagentsKey` (line 41):

```swift
    private static let showUsageStatsKey = "showUsageStats"
```

In `init` next to the `showSubagents` load (line 59):

```swift
        self.showUsageStats = UserDefaults.standard.bool(forKey: Self.showUsageStatsKey)
```

(Defaults false — the toggle ships off.)

- [ ] **Step 2: Create the scanner**

Create `Sources/ClaudeLightApp/UsageScanner.swift`:

```swift
import Foundation
import Combine
import ClaudeLightCore

/// What the usage surfaces render: current-window burn + reset, today's burn
/// (the history view's live row — the stats cache lags a day), and the cached
/// daily history.
struct UsageSnapshot: Equatable {
    var windowBurn: [ModelBurn] = []
    var windowEnd: Date?
    var todayBurn: [ModelBurn] = []
    var dailyHistory: [DailyModelTokens] = []
}

/// Scans recently-modified transcripts for per-model window burn (#83).
/// The scan NEVER runs on the main actor — the archived quota-window attempt
/// died on a ~200ms synchronous parse per reload. Work happens in a detached
/// task over a stamp-memoized per-file cache; only the published snapshot
/// assignment touches main.
@MainActor
final class UsageScanner: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()

    private var scanning = false
    private var lastScan = Date.distantPast
    private let cache = FileMemoCache<[UsageEntry]>()

    /// How far back transcript mtimes are considered. The window anchor needs
    /// history back to the last ≥5h idle gap; 24h reaches it in practice
    /// (if no gap exists in 24h, the anchor approximates at the oldest
    /// scanned activity).
    static let lookback: TimeInterval = 24 * 3600
    static let maxTailBytes = 4 * 1024 * 1024
    static let minScanInterval: TimeInterval = 30

    func refresh(force: Bool = false) {
        guard !scanning,
              force || Date().timeIntervalSince(lastScan) >= Self.minScanInterval else { return }
        scanning = true
        let cache = self.cache   // bind before detaching (CI strict concurrency)
        Task { [weak self] in
            let snap = await Task.detached(priority: .utility) {
                Self.scan(cache: cache)
            }.value
            self?.snapshot = snap
            self?.scanning = false
            self?.lastScan = Date()
        }
    }

    // MARK: - Off-main scan (static: no self capture in the detached task)

    /// The cache is touched only here, and scans are serialized by the
    /// `scanning` flag — no concurrent mutation.
    nonisolated static func scan(cache: FileMemoCache<[UsageEntry]>, now: Date = Date()) -> UsageSnapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent(".claude/projects")
        let paths = transcriptPaths(root: root, since: now.addingTimeInterval(-lookback))

        var entries: [UsageEntry] = []
        for path in paths {
            guard let stamp = stamp(path: path) else { continue }
            entries += cache.value(for: path, stamp: stamp) {
                tailText(path: path, maxBytes: maxTailBytes)
                    .map(usageEntries(transcriptJSONL:)) ?? []
            }
        }
        cache.evict(keeping: Set(paths))
        entries.sort { $0.timestamp < $1.timestamp }

        var snap = UsageSnapshot()
        if let window = currentUsageWindow(now: now, timestamps: entries.map(\.timestamp)) {
            snap.windowBurn = usageByModel(entries, from: window.start, to: window.end)
            snap.windowEnd = window.end
        }
        let dayStart = Calendar.current.startOfDay(for: now)
        snap.todayBurn = usageByModel(entries, from: dayStart, to: now.addingTimeInterval(1))

        let cacheURL = home.appendingPathComponent(".claude/stats-cache.json")
        if let data = try? Data(contentsOf: cacheURL) {
            snap.dailyHistory = dailyModelTokens(fromJSON: data)
        }
        return snap
    }

    nonisolated static func transcriptPaths(root: URL, since: Date) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var out: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let mtime = values?.contentModificationDate, mtime >= since {
                out.append(url.path)
            }
        }
        return out
    }

    nonisolated static func stamp(path: String) -> FileStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? NSNumber else { return nil }
        return FileStamp(mtime: mtime, size: size.uint64Value)
    }

    /// Bounded tail read, lossy-decoded — a live transcript's tail can be torn
    /// mid-UTF-8 (#111) and its first line mid-JSON; `usageEntries` skips both.
    nonisolated static func tailText(path: String, maxBytes: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 3: Build and run the full suite**

Run: `swift build && swift test`
Expected: build clean; all tests pass (no regressions — this task adds code, changes no behavior yet).

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/UsageScanner.swift Sources/ClaudeLightApp/SessionWatcher.swift
git commit -m "feat: off-main usage scanner + showUsageStats setting"
```

---

### Task 5: App — UsageRow (variant B) docked in the panel + Settings toggle

**Files:**
- Create: `Sources/ClaudeLightApp/UsageRow.swift`
- Modify: `Sources/ClaudeLightApp/PanelContent.swift` (dock the row at the reserved #83 slot; scanner wiring; height estimate)
- Modify: `Sources/ClaudeLightApp/SettingsPane.swift` (the toggle, in the checkbox group at lines 36-47)

**Interfaces:**
- Consumes: `UsageScanner`/`UsageSnapshot` (Task 4), `ModelBurn`, `tokenText`, `resetText`, `modelColorSlot`, `shortModelName` (Core).
- Produces: `UsagePalette.color(forModel:)` and `UsagePalette.color(for slot:)` (Task 6 reuses); `UsageRow(burn:windowEnd:now:onOpen:)`; `PanelContent.showingUsage` state (Task 6 fills the pane).

View code — no unit tests; verify by build + suite + live check in Task 7.

- [ ] **Step 1: Create the row view**

Create `Sources/ClaudeLightApp/UsageRow.swift`:

```swift
import SwiftUI
import ClaudeLightCore

/// Model colors — categorical palette validated for colorblind separation and
/// ≥3:1 contrast on the dark panel (2026-07-06 usage-stats spec). Fixed per
/// family, never cycled. Red/orange/green are reserved for session status.
enum UsagePalette {
    static func color(for slot: ModelColorSlot) -> Color {
        switch slot {
        case .fable:  return Color(red: 0.224, green: 0.529, blue: 0.898) // #3987e5
        case .opus:   return Color(red: 0.098, green: 0.620, blue: 0.439) // #199e70
        case .sonnet: return Color(red: 0.788, green: 0.522, blue: 0.000) // #c98500
        case .haiku:  return Color(red: 0.565, green: 0.522, blue: 0.914) // #9085e9
        case .other:  return Color.primary.opacity(0.35)
        }
    }
    static func color(forModel id: String) -> Color { color(for: modelColorSlot(id)) }

    /// Chip label: family name for known models, short id for others.
    static func chipName(_ id: String) -> String {
        switch modelColorSlot(id) {
        case .fable: return "FABLE"
        case .opus: return "OPUS"
        case .sonnet: return "SONNET"
        case .haiku: return "HAIKU"
        case .other: return shortModelName(id).uppercased()
        }
    }
}

/// The usage glance (#83, mockup variant B): a thin composition micro-bar of
/// the current 5h window's burn (segments relative to each other — never to a
/// cap), model chips beneath, reset countdown at the trailing edge. The whole
/// row is a button into the Usage view.
struct UsageRow: View {
    let burn: [ModelBurn]      // descending, from the scanner
    let windowEnd: Date?
    let now: Date
    let onOpen: () -> Void

    private static let maxChips = 3

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 5) {
                microbar
                chips
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .accessibilityLabel(accessibilityText)
    }

    private var total: Int { burn.reduce(0) { $0 + $1.tokens } }

    private var microbar: some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(burn.count - 1, 0)) * 2
            let available = max(geo.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(burn, id: \.model) { b in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(UsagePalette.color(forModel: b.model))
                        .frame(width: max(3, available * CGFloat(b.tokens) / CGFloat(max(total, 1))))
                }
            }
        }
        .frame(height: 5)
    }

    private var chips: some View {
        HStack(spacing: 10) {
            ForEach(burn.prefix(Self.maxChips), id: \.model) { b in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(UsagePalette.color(forModel: b.model))
                        .frame(width: 6, height: 6)
                    Text(UsagePalette.chipName(b.model))
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(.secondary)
                    Text(tokenText(b.tokens))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if burn.count > Self.maxChips {
                Text("+\(burn.count - Self.maxChips)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let end = windowEnd {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9))
                    Text(resetText(until: end, now: now))
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var accessibilityText: String {
        let parts = burn.map { "\(UsagePalette.chipName($0.model)) \(tokenText($0.tokens))" }
        let reset = windowEnd.map { ", window resets in \(resetText(until: $0, now: now))" } ?? ""
        return "Usage: " + parts.joined(separator: ", ") + reset
    }
}
```

- [ ] **Step 2: Dock the row in PanelContent**

In `Sources/ClaudeLightApp/PanelContent.swift`:

Add state next to `showingSettings`:

```swift
    @State private var showingUsage = false
    @StateObject private var usage = UsageScanner()
```

Replace the footer block inside `sessionList(now:)` (currently the `// Stats strip (#83) docks…` comment, `Divider()`, `footer`):

```swift
            // Stats strip (#83): the usage glance docks between the list and footer.
            if watcher.showUsageStats, !usage.snapshot.windowBurn.isEmpty {
                Divider()
                UsageRow(burn: usage.snapshot.windowBurn,
                         windowEnd: usage.snapshot.windowEnd,
                         now: now) { showingUsage = true }
            }
            Divider()
            footer
```

Wire refresh onto the body `Group` (after `.frame(width: 340)`):

```swift
        .onAppear { if watcher.showUsageStats { usage.refresh(force: true) } }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if watcher.showUsageStats { usage.refresh() }
        }
```

(The Timer publisher only fires while the panel view exists — no cost when closed. The scanner's own `minScanInterval` + stamp memoization bound repeat work.)

Update the height estimate (`estimatedRowWeight`) to count the row:

```swift
        let usageRow = (watcher.showUsageStats && !usage.snapshot.windowBurn.isEmpty) ? 1 : 0
        return watcher.sessions.count + subagentRows / 3 + usageRow
```

- [ ] **Step 3: Add the Settings toggle**

In `Sources/ClaudeLightApp/SettingsPane.swift`, inside the checkbox `VStack` (after the `Show subagents` toggle at line 37):

```swift
                Toggle("Show usage stats", isOn: $watcher.showUsageStats)
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: build clean; all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightApp/UsageRow.swift Sources/ClaudeLightApp/PanelContent.swift Sources/ClaudeLightApp/SettingsPane.swift
git commit -m "feat: usage glance row docked above footer + Settings toggle"
```

---

### Task 6: App — UsageView (dedicated pane) + flip wiring

**Files:**
- Create: `Sources/ClaudeLightApp/UsageView.swift`
- Modify: `Sources/ClaudeLightApp/PanelContent.swift` (pane flip for `showingUsage`)

**Interfaces:**
- Consumes: `UsageSnapshot` (Task 4), `UsagePalette` (Task 5), `tokenText`, `resetText`, `modelColorSlot`, `ModelColorSlot`, `DailyModelTokens`, `ModelBurn` (Core).
- Produces: `UsageView(snapshot:now:onBack:)`.

- [ ] **Step 1: Create the view**

Create `Sources/ClaudeLightApp/UsageView.swift`:

```swift
import SwiftUI
import ClaudeLightCore

/// The dedicated usage pane (#83): current-window per-model bars + reset,
/// then daily history (Claude Code's stats cache + a live `today` row).
/// Same flip mechanism and rhythm as SettingsPane.
struct UsageView: View {
    let snapshot: UsageSnapshot
    let now: Date
    let onBack: () -> Void

    /// Stacked segments keep FIXED model order so days compare visually
    /// (the live row sorts by burn instead — a composition reads best
    /// biggest-first, a stack needs stable order).
    private static let stackOrder: [ModelColorSlot] = [.fable, .opus, .sonnet, .haiku, .other]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().padding(.horizontal, -10)

            if snapshot.windowBurn.isEmpty && days.isEmpty {
                Text("No usage recorded yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                currentWindow
                Divider().padding(.horizontal, -10)
                daily
                Divider().padding(.horizontal, -10)
                footnote
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 22)
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("Back").font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            Text("Usage").font(.system(size: 12, weight: .semibold))
            Spacer()
            // Mirror the back control's width so the title stays centered.
            HStack(spacing: 3) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                Text("Back").font(.system(size: 12))
            }.hidden()
        }
    }

    // MARK: - Current window

    @ViewBuilder private var currentWindow: some View {
        if !snapshot.windowBurn.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                sectionTitle("Current window")
                let maxTokens = snapshot.windowBurn.first?.tokens ?? 1
                ForEach(snapshot.windowBurn, id: \.model) { b in
                    HStack(spacing: 8) {
                        modelLabel(b.model).frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.08))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(UsagePalette.color(forModel: b.model))
                                    .frame(width: geo.size.width * CGFloat(b.tokens) / CGFloat(max(maxTokens, 1)))
                            }
                        }
                        .frame(height: 8)
                        Text(tokenText(b.tokens))
                            .font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                if let end = snapshot.windowEnd {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9))
                        Text("window resets in ").font(.system(size: 11))
                        + Text(resetText(until: end, now: now))
                            .font(.system(size: 11, weight: .semibold))
                        + Text(" · \(Self.wallClock.string(from: end))")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                }
            }
        }
    }

    // MARK: - Daily history

    private struct Day: Identifiable {
        let id: String            // date key or "today"
        let label: String
        let tokensByModel: [String: Int]
        let isToday: Bool
        var total: Int { tokensByModel.values.reduce(0, +) }
    }

    /// Last 4 cache days before today + a live `today` row. The live number
    /// wins over any cache entry for today — the cache lags a day.
    private var days: [Day] {
        let todayKey = Self.dayKey.string(from: now)
        var rows: [Day] = snapshot.dailyHistory
            .filter { $0.date < todayKey }
            .sorted { $0.date < $1.date }
            .suffix(4)
            .map { Day(id: $0.date, label: Self.dayLabel($0.date),
                       tokensByModel: $0.tokensByModel, isToday: false) }
        if !snapshot.todayBurn.isEmpty {
            let tokens = Dictionary(uniqueKeysWithValues: snapshot.todayBurn.map { ($0.model, $0.tokens) })
            rows.append(Day(id: "today", label: "today", tokensByModel: tokens, isToday: true))
        }
        return rows
    }

    @ViewBuilder private var daily: some View {
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                sectionTitle("Daily · last \(days.count) days")
                let maxTotal = days.map(\.total).max() ?? 1
                ForEach(days) { day in
                    HStack(spacing: 8) {
                        Text(day.label)
                            .font(.system(size: 10, weight: day.isToday ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(day.isToday ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                            .frame(width: 44, alignment: .leading)
                        GeometryReader { geo in
                            let segments = slotTotals(day.tokensByModel)
                            let scale = CGFloat(day.total) / CGFloat(max(maxTotal, 1))
                            let gaps = CGFloat(max(segments.count - 1, 0)) * 2
                            let available = max(geo.size.width * scale - gaps, 0)
                            HStack(spacing: 2) {
                                ForEach(segments, id: \.slot.hashValue) { seg in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(UsagePalette.color(for: seg.slot))
                                        .frame(width: max(3, available * CGFloat(seg.tokens) / CGFloat(max(day.total, 1))))
                                }
                            }
                        }
                        .frame(height: 8)
                        .help(hoverText(day))
                        Text(tokenText(day.total))
                            .font(.system(size: 10)).monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                legend
            }
        }
    }

    private func slotTotals(_ tokens: [String: Int]) -> [(slot: ModelColorSlot, tokens: Int)] {
        var sums: [ModelColorSlot: Int] = [:]
        for (model, t) in tokens { sums[modelColorSlot(model), default: 0] += t }
        return Self.stackOrder.compactMap { slot in sums[slot].map { (slot, $0) } }
    }

    private func hoverText(_ day: Day) -> String {
        slotTotals(day.tokensByModel)
            .map { "\(slotName($0.slot)) \(tokenText($0.tokens))" }
            .joined(separator: " · ")
    }

    private var legend: some View {
        let slots = Self.stackOrder.filter { slot in
            days.contains { day in day.tokensByModel.contains { modelColorSlot($0.key) == slot } }
        }
        return HStack(spacing: 12) {
            ForEach(slots, id: \.hashValue) { slot in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(UsagePalette.color(for: slot))
                        .frame(width: 6, height: 6)
                    Text(slotName(slot))
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func slotName(_ slot: ModelColorSlot) -> String {
        switch slot {
        case .fable: return "FABLE"
        case .opus: return "OPUS"
        case .sonnet: return "SONNET"
        case .haiku: return "HAIKU"
        case .other: return "OTHER"
        }
    }

    private var footnote: some View {
        Text("Local only — window from your transcripts, history from Claude Code's stats cache. No caps are exposed, so bars compare models to each other, never to a limit.")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .kerning(1)
            .foregroundStyle(.tertiary)
    }

    private func modelLabel(_ id: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(UsagePalette.color(forModel: id))
                .frame(width: 6, height: 6)
            Text(UsagePalette.chipName(id))
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Date helpers

    private static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let dayOut: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    private static let wallClock: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
    private static func dayLabel(_ key: String) -> String {
        dayKey.date(from: key).map { dayOut.string(from: $0) } ?? key
    }
}
```

- [ ] **Step 2: Wire the pane flip in PanelContent**

In `Sources/ClaudeLightApp/PanelContent.swift`, extend the body `Group`'s branches (currently `if showingSettings … else …`):

```swift
        Group {
            if showingSettings {
                SettingsPane(watcher: watcher) { showingSettings = false }
            } else if showingUsage {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    UsageView(snapshot: usage.snapshot, now: context.date) { showingUsage = false }
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    sessionList(now: context.date)
                }
            }
        }
```

- [ ] **Step 3: Build and run the full suite**

Run: `swift build && swift test`
Expected: build clean; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/UsageView.swift Sources/ClaudeLightApp/PanelContent.swift
git commit -m "feat: dedicated Usage view with current window + daily history"
```

---

### Task 7: Core — plan limits decoding & urgency mapping

**Files:**
- Create: `Sources/ClaudeLightCore/PlanLimits.swift`
- Test: `Tests/ClaudeLightCoreTests/PlanLimitsTests.swift`

**Interfaces:**
- Consumes: `ContextLevel` + `contextLevel(fraction:)` (existing, `PanelModel.swift:55-65`), `resetText` (Task 3).
- Produces:
  - `public struct PlanLimit: Equatable, Sendable { let kind: String; let label: String; let percent: Int; let severity: String; let resetsAt: Date? }`
  - `public func planLimits(fromJSON data: Data) -> [PlanLimit]`
  - `public func limitLevel(_ limit: PlanLimit) -> ContextLevel`
  - `public func limitResetText(kind: String, resetsAt: Date?, now: Date) -> String?`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeLightCoreTests/PlanLimitsTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class PlanLimitsTests: XCTestCase {
    /// Real response shape, captured live 2026-07-06.
    private let realShape = """
    {"five_hour":{"utilization":9.0},"limits":[
      {"kind":"session","group":"session","percent":9,"severity":"normal","resets_at":"2026-07-06T05:00:00.330921+00:00","scope":null,"is_active":false},
      {"kind":"weekly_all","group":"weekly","percent":33,"severity":"normal","resets_at":"2026-07-07T19:00:00.330945+00:00","scope":null,"is_active":false},
      {"kind":"weekly_scoped","group":"weekly","percent":53,"severity":"normal","resets_at":"2026-07-07T19:00:00.331249+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true}
    ]}
    """.data(using: .utf8)!

    func test_decodesRealShape_withLabelsAndDates() {
        let limits = planLimits(fromJSON: realShape)
        XCTAssertEqual(limits.count, 3)
        XCTAssertEqual(limits[0].kind, "session")
        XCTAssertEqual(limits[0].label, "Session")
        XCTAssertEqual(limits[0].percent, 9)
        XCTAssertNotNil(limits[0].resetsAt)   // 6-digit fractional offset form must parse
        XCTAssertEqual(limits[1].label, "Week · all")
        XCTAssertEqual(limits[2].label, "Week · Fable")   // scope display name
        XCTAssertEqual(limits[2].percent, 53)
    }

    func test_unknownKind_keptWithKindAsLabel() {
        let json = Data(#"{"limits":[{"kind":"monthly_beta","percent":10,"severity":"normal"}]}"#.utf8)
        let limits = planLimits(fromJSON: json)
        XCTAssertEqual(limits.first?.label, "monthly_beta")
        XCTAssertNil(limits.first?.resetsAt)   // missing resets_at tolerated
    }

    func test_garbledOrMissingLimits_returnsEmpty() {
        XCTAssertTrue(planLimits(fromJSON: Data(#"{"limits":"nope"}"#.utf8)).isEmpty)
        XCTAssertTrue(planLimits(fromJSON: Data(#"{"five_hour":{}}"#.utf8)).isEmpty)
        XCTAssertTrue(planLimits(fromJSON: Data("not json".utf8)).isEmpty)
    }

    func test_limitLevel_thresholdsAndSeverityOverride() {
        func limit(_ pct: Int, severity: String = "normal") -> PlanLimit {
            PlanLimit(kind: "session", label: "Session", percent: pct, severity: severity, resetsAt: nil)
        }
        XCTAssertEqual(limitLevel(limit(9)), .ok)
        XCTAssertEqual(limitLevel(limit(75)), .warm)
        XCTAssertEqual(limitLevel(limit(90)), .hot)
        XCTAssertEqual(limitLevel(limit(10, severity: "warning")), .warm)   // server flag wins
        XCTAssertEqual(limitLevel(limit(10, severity: "exceeded")), .hot)
    }

    func test_limitResetText_sessionCountdown_weeklyWallclock() {
        let now = ISO8601DateFormatter().date(from: "2026-07-06T02:24:00Z")!
        let sessionReset = ISO8601DateFormatter().date(from: "2026-07-06T05:00:00Z")!
        XCTAssertEqual(limitResetText(kind: "session", resetsAt: sessionReset, now: now), "2h 36m")
        XCTAssertNil(limitResetText(kind: "session", resetsAt: nil, now: now))
        // Weekly form is weekday + time; exact string depends on local timezone,
        // so assert shape, not value.
        let weekly = limitResetText(kind: "weekly_all", resetsAt: sessionReset, now: now)
        XCTAssertNotNil(weekly)
        XCTAssertFalse(weekly!.contains("h "))   // not a countdown
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PlanLimitsTests`
Expected: FAIL — `PlanLimit` / `planLimits` / `limitLevel` / `limitResetText` undefined.

- [ ] **Step 3: Implement**

Create `Sources/ClaudeLightCore/PlanLimits.swift`:

```swift
import Foundation

/// One plan-limit bucket from Anthropic's OAuth usage endpoint (#83) — the
/// same data `/usage` shows: session (5h), weekly all-models, and weekly
/// model-scoped (e.g. Fable's own cap). Percentages are REAL — they come
/// from Anthropic, not from local guessing.
public struct PlanLimit: Equatable, Sendable {
    public let kind: String        // "session" | "weekly_all" | "weekly_scoped" | future kinds
    public let label: String       // display label, derived from kind + scope
    public let percent: Int
    public let severity: String    // "normal" unless the server flags otherwise
    public let resetsAt: Date?

    public init(kind: String, label: String, percent: Int, severity: String, resetsAt: Date?) {
        self.kind = kind
        self.label = label
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
    }
}

// The endpoint writes 6-digit fractional offsets ("…T05:00:00.330921+00:00");
// ISO8601DateFormatter is unreliable past 3 digits, so a POSIX DateFormatter
// leads and ISO8601 forms are fallbacks.
private let limitsFractional: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
    return f
}()
private let limitsISOFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let limitsISOPlain = ISO8601DateFormatter()

private func parseLimitDate(_ s: String) -> Date? {
    limitsFractional.date(from: s) ?? limitsISOFractional.date(from: s) ?? limitsISOPlain.date(from: s)
}

/// Tolerant decode of the response's `limits` array — every other key is
/// ignored, any surprise degrades to fewer rows or `[]`, never an error.
/// Unknown kinds are kept (labeled by their kind) so future buckets appear
/// rather than vanish.
public func planLimits(fromJSON data: Data) -> [PlanLimit] {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = obj["limits"] as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
        guard let kind = row["kind"] as? String,
              let percent = (row["percent"] as? NSNumber)?.intValue else { return nil }
        let severity = row["severity"] as? String ?? "normal"
        let resetsAt = (row["resets_at"] as? String).flatMap(parseLimitDate)
        let scopeName = ((row["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
        let label: String
        switch kind {
        case "session": label = "Session"
        case "weekly_all": label = "Week · all"
        case "weekly_scoped": label = "Week · \(scopeName ?? "scoped")"
        default: label = kind
        }
        return PlanLimit(kind: kind, label: label, percent: percent,
                         severity: severity, resetsAt: resetsAt)
    }
}

/// Urgency for a limit bar — the context gauge's bands, so the panel speaks
/// one urgency language. A non-normal server severity outranks the threshold.
public func limitLevel(_ limit: PlanLimit) -> ContextLevel {
    switch limit.severity {
    case "normal": return contextLevel(fraction: Double(limit.percent) / 100)
    case "warning": return .warm
    default: return .hot
    }
}

private let weekdayClock: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE H:mm"
    return f
}()

/// Session limits show a countdown ("2h 36m"); weekly limits show the
/// wall-clock reset ("Wed 2:00"). Nil when the server sent no reset.
public func limitResetText(kind: String, resetsAt: Date?, now: Date) -> String? {
    guard let resetsAt else { return nil }
    return kind == "session" ? resetText(until: resetsAt, now: now)
                             : weekdayClock.string(from: resetsAt)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PlanLimitsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/PlanLimits.swift Tests/ClaudeLightCoreTests/PlanLimitsTests.swift
git commit -m "feat: plan-limits decoding and urgency mapping"
```

---

### Task 8: App — Keychain token read + limits fetcher + settings flag

**Files:**
- Create: `Sources/ClaudeLightApp/LimitsFetcher.swift`
- Modify: `Sources/ClaudeLightApp/SessionWatcher.swift` (add `showPlanLimits`, mirroring `showUsageStats` from Task 4)

**Interfaces:**
- Consumes: `PlanLimit`, `planLimits(fromJSON:)` (Task 7).
- Produces:
  - `@MainActor final class LimitsFetcher: ObservableObject` with `@Published private(set) var limits: [PlanLimit]` and `func refresh(force: Bool = false)`
  - `SessionWatcher.showPlanLimits: Bool` (`@Published`, UserDefaults key `"showPlanLimits"`, default false)

App plumbing over the tested decoder — no new unit tests; verify by build + suite.

- [ ] **Step 1: Add the settings flag to SessionWatcher**

Exactly like `showUsageStats` (Task 4): property with `didSet` persist, key constant `"showPlanLimits"`, `UserDefaults.standard.bool` load in `init`.

```swift
    @Published var showPlanLimits: Bool {
        didSet {
            UserDefaults.standard.set(showPlanLimits, forKey: Self.showPlanLimitsKey)
        }
    }
```
```swift
    private static let showPlanLimitsKey = "showPlanLimits"
```
```swift
        self.showPlanLimits = UserDefaults.standard.bool(forKey: Self.showPlanLimitsKey)
```

- [ ] **Step 2: Create the fetcher**

Create `Sources/ClaudeLightApp/LimitsFetcher.swift`:

```swift
import Foundation
import Combine
import Security
import ClaudeLightCore

/// Fetches the account's real plan-limit levels (#83) from Anthropic's OAuth
/// usage endpoint — the same read `/usage` performs. Strictly additive with
/// silent fallback: no Keychain item, denied access, 401, offline, or a
/// reshaped response all yield empty limits and hide the section; never an
/// error state. The token is read from the Keychain item Claude Code itself
/// maintains, used once in an Authorization header, and never logged,
/// persisted, or sent anywhere else.
@MainActor
final class LimitsFetcher: ObservableObject {
    @Published private(set) var limits: [PlanLimit] = []

    private var fetching = false
    private var lastFetch = Date.distantPast
    static let minInterval: TimeInterval = 300   // politeness toward an unofficial endpoint

    func refresh(force: Bool = false) {
        guard !fetching,
              force || Date().timeIntervalSince(lastFetch) >= Self.minInterval else { return }
        fetching = true
        Task { [weak self] in
            let fetched = await Task.detached(priority: .utility) {
                Self.fetch()
            }.value
            self?.limits = fetched
            self?.fetching = false
            self?.lastFetch = Date()
        }
    }

    // MARK: - Off-main work (static: no self capture in the detached task)

    nonisolated static func fetch() async -> [PlanLimit] {
        guard let token = keychainToken() else { return [] }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return planLimits(fromJSON: data)
    }

    /// Claude Code stores its OAuth credentials at login; we only read them.
    /// First read triggers macOS's one-time permission prompt — deny is a
    /// supported answer (empty limits).
    nonisolated static func keychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }
}
```

- [ ] **Step 3: Build and run the full suite**

Run: `swift build && swift test`
Expected: build clean; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/LimitsFetcher.swift Sources/ClaudeLightApp/SessionWatcher.swift
git commit -m "feat: opt-in plan-limits fetcher (Keychain token, silent fallback)"
```

---

### Task 9: App — Plan limits UI (Usage view section, row reset upgrade, Settings toggle)

**Files:**
- Modify: `Sources/ClaudeLightApp/UsageView.swift` (Plan limits section above Current window)
- Modify: `Sources/ClaudeLightApp/PanelContent.swift` (fetcher wiring, row reset override, pass limits to the view)
- Modify: `Sources/ClaudeLightApp/SettingsPane.swift` (second toggle + caption)

**Interfaces:**
- Consumes: `LimitsFetcher` (Task 8), `PlanLimit`, `limitLevel`, `limitResetText` (Task 7), `UsageView`/`UsageRow` (Tasks 5-6), `ContextLevel`.
- Produces: `UsageView(snapshot:limits:now:onBack:)` (signature gains `limits: [PlanLimit]`).

View code — verify by build + suite + live check in Task 10.

- [ ] **Step 1: Add the Plan limits section to UsageView**

In `Sources/ClaudeLightApp/UsageView.swift`: add the property and section.

Add to the struct's stored properties:

```swift
    let limits: [PlanLimit]
```

In `body`, insert before `currentWindow` (inside the non-empty branch):

```swift
                if !limits.isEmpty {
                    planLimitsSection
                    Divider().padding(.horizontal, -10)
                }
```

Also change the empty check so limits count as content:

```swift
            if snapshot.windowBurn.isEmpty && days.isEmpty && limits.isEmpty {
```

Add the section and its color helper:

```swift
    // MARK: - Plan limits (fetched — real percentages)

    @ViewBuilder private var planLimitsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionTitle("Plan limits")
            ForEach(limits, id: \.kind) { limit in
                HStack(spacing: 8) {
                    Text(limit.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.08))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Self.levelColor(limitLevel(limit)))
                                .frame(width: geo.size.width * CGFloat(min(limit.percent, 100)) / 100)
                        }
                    }
                    .frame(height: 8)
                    Text("\(limit.percent)%")
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    Text(resetLabel(limit))
                        .font(.system(size: 10)).monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 58, alignment: .trailing)
                        .lineLimit(1)
                }
            }
        }
    }

    private func resetLabel(_ limit: PlanLimit) -> String {
        limitResetText(kind: limit.kind, resetsAt: limit.resetsAt, now: now).map { "↻ \($0)" } ?? ""
    }

    /// Capacity bars speak the context gauge's urgency language — never the
    /// model categorical palette (capacity, not identity).
    private static func levelColor(_ level: ContextLevel) -> Color {
        switch level {
        case .ok: return Color.primary.opacity(0.75)
        case .warm: return PanelPalette.orange
        case .hot: return PanelPalette.red
        }
    }
```

Note: `resetLabel` uses the text glyph `↻` inside a `Text` next to values — if it renders poorly in the system font during live verify (the `⑂` lesson), swap to an `Image(systemName: "arrow.clockwise")` + `Text` pair like the row does. Flag it for the Task 10 live check.

Update the footnote to cover the fetched section:

```swift
    private var footnote: some View {
        Text("Plan limits come from Anthropic with your Claude Code login (opt-in). Everything else is local — window from your transcripts, history from Claude Code's stats cache; those bars compare models to each other, never to a limit.")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }
```

- [ ] **Step 2: Wire the fetcher in PanelContent**

In `Sources/ClaudeLightApp/PanelContent.swift`:

Add next to the scanner:

```swift
    @StateObject private var limitsFetcher = LimitsFetcher()
```

Extend the refresh wiring (the `.onAppear` / `.onReceive` added in Task 5):

```swift
        .onAppear {
            if watcher.showUsageStats { usage.refresh(force: true) }
            if watcher.showPlanLimits { limitsFetcher.refresh(force: true) }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if watcher.showUsageStats { usage.refresh() }
            if watcher.showPlanLimits { limitsFetcher.refresh() }   // fetcher self-throttles to 5 min
        }
```

Pass limits into the Usage pane (Task 6's branch):

```swift
            } else if showingUsage {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    UsageView(snapshot: usage.snapshot,
                              limits: watcher.showPlanLimits ? limitsFetcher.limits : [],
                              now: context.date) { showingUsage = false }
                }
            }
```

Upgrade the row's reset to Anthropic's session clock when available (Task 5's row call):

```swift
                let sessionReset = watcher.showPlanLimits
                    ? limitsFetcher.limits.first(where: { $0.kind == "session" })?.resetsAt
                    : nil
                UsageRow(burn: usage.snapshot.windowBurn,
                         windowEnd: sessionReset ?? usage.snapshot.windowEnd,
                         now: now) { showingUsage = true }
```

- [ ] **Step 3: Add the Settings toggle + caption**

In `Sources/ClaudeLightApp/SettingsPane.swift`, after the `Show usage stats` toggle:

```swift
                Toggle("Show plan limits", isOn: $watcher.showPlanLimits)
                Text("Reads your Claude Code login from the Keychain to fetch limits from Anthropic. Nothing else is sent.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: build clean; all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightApp/UsageView.swift Sources/ClaudeLightApp/PanelContent.swift Sources/ClaudeLightApp/SettingsPane.swift
git commit -m "feat: plan-limits bars in Usage view, real session reset in row, Settings toggle"
```

---

### Task 10: Live verification, review & PR

**Files:** none (verification only).

- [ ] **Step 1: Live-verify against the mockup and the spec's success criteria**

Build and run the branch app (`swift run ClaudeLightApp` — a second menu-bar icon appears next to the installed one; quit it after).

Check, against the approved mockup (variant B row + dedicated view) and the spec's success criteria:
- Toggle OFF (default): panel identical to v0.17.0's — no row, no divider change.
- Toggle ON in Settings: the micro-bar row appears above the footer with the current window's models, descending, reset countdown at the right; fixed height (numbers changing must not reflow the panel).
- Click the row → Usage view: current-window bars, reset line with wall-clock, daily history with a bold `today` row, legend, footnote. Back returns to sessions.
- Sanity-check the numbers: today's row against `/usage` in a Claude Code session; daily history against `~/.claude/stats-cache.json` values.
- Plan limits: toggle "Show plan limits" ON → macOS Keychain prompt appears once → Allow → the three bars appear and match `/usage`'s percentages and reset times; the row's session reset switches to Anthropic's clock. Toggle OFF or Deny → section absent, no error anywhere. Check the `↻` glyph renders cleanly next to the reset labels (swap to the SF Symbol pair if not — the `⑂` lesson).
- No perceptible lag opening the panel (scan is off-main and memoized; fetch is async).
- With no activity in 5h (or by temporarily setting `lookback` low in a scratch run), the row hides rather than showing zeros.

- [ ] **Step 2: Full suite once more**

Run: `swift test`
Expected: PASS.

- [ ] **Step 3: Request code review**

Whole-branch review before PR (superpowers:requesting-code-review / the SDD final review).

- [ ] **Step 4: Open the PR**

```bash
git push -u origin feat/usage-stats
gh pr create --title "feat: usage stats — model window burn, plan limits, reset (#83)" \
  --body "Toggleable usage glance: per-model token burn in the current 5h window (micro-bar row above the footer) + reset countdown, and a dedicated Usage view with REAL plan-limit bars (opt-in fetch from Anthropic's OAuth usage endpoint via the Keychain token Claude Code already stores — silent fallback when unavailable) plus daily per-model history. Spec: docs/superpowers/specs/2026-07-06-usage-stats-design.md. Third probe of #83 — scoped to model rationing."
```

---

## Self-Review

**Spec coverage:** Window tiling + basis → Task 1. Cache decode → Task 2. Formatting/slots → Task 3. Off-main scanner + 24h lookback + today burn + history load → Task 4. Row (variant B: micro-bar, ≤3 chips + `+N`, reset symbol, hide-when-empty, click-through, placement, height estimate) → Task 5. View (current window, daily w/ fixed stack order + live today + hover + legend + footnote, empty state) → Task 6. Toggle default-off → Tasks 4-5, 8-9. Palette/status-color rule → Task 5 (`UsagePalette`); capacity-bar urgency rule → Tasks 7 (`limitLevel`) + 9 (`levelColor`). Limits decode → Task 7. Keychain read + fetch + silent fallback + 5-min throttle → Task 8. Plan-limits section, row reset upgrade, Settings caption → Task 9. Success criteria → Task 10. Learned ceiling explicitly out of scope — no task, per spec.

**Placeholder scan:** none — every code step is complete.

**Type consistency:** `UsageEntry`/`ModelBurn`/`DailyModelTokens`/`ModelColorSlot` signatures match across Tasks 1-6; `UsageSnapshot` fields (`windowBurn`, `windowEnd`, `todayBurn`, `dailyHistory`) consistent between Tasks 4, 5, 6; `UsagePalette.color(for:)`/`color(forModel:)`/`chipName` defined in Task 5, consumed in Task 6; `refresh(force:)` matches between Tasks 4/8 and their PanelContent call sites; `PlanLimit`/`planLimits`/`limitLevel`/`limitResetText` (Task 7) match Task 8's fetch and Task 9's view usage; `UsageView` gains `limits: [PlanLimit]` consistently between Tasks 9's view and PanelContent call.

Fork resolved 2026-07-06: opt-in fetch approved by the user; Tasks 7-9 implement it. Endpoint verified live (HTTP 200) before planning.
