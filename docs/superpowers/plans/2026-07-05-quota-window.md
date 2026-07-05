# Quota Window Header Countdown Implementation Plan (#83)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The panel header shows "↻ 2h 10m" until the current 5-hour usage window resets, with tokens/models/reset detail in its tooltip.

**Architecture:** Read-side only. Pure Core functions extract per-entry usage events from transcript JSONL and fold them into the current 5-hour block; a Core scanner walks `~/.claude/projects` for transcripts touched in the last 6 hours with `FileMemoCache` memoization; SessionWatcher recomputes on reload and publishes; the header renders the countdown off the existing 1-second `TimelineView`. No hook changes. Spec: `docs/superpowers/specs/2026-07-05-quota-window-design.md`.

**Tech Stack:** Swift 5 / Foundation, XCTest, SwiftUI (header only).

## Global Constraints

- No hook changes; no new files written anywhere — transcripts are read-only input.
- Tokens per entry = `input_tokens + cache_creation_input_tokens + output_tokens`; cache reads excluded.
- Block math: anchor = first entry after the most recent gap ≥ 5h (or earliest entry); current block start = `anchor + 5h × floor((now − anchor)/5h)`; reset = start + 5h; newest entry older than 5h → no active window (nil).
- Only transcripts with mtime within the last 6 hours are read; per-file parse memoized by (path, mtime, size) via the existing `FileMemoCache`.
- Display: countdown "Nh Mm" / "Nm" / "<1m", tertiary 11pt, right of the header summary; hidden (no placeholder) when nil. Tooltip: "2.4M tokens since 12:00 across 3 sessions · resets at 17:00 · models: fable-5, sonnet-5". Never a percentage.
- JSONL parsing is line-tolerant (skip undecodable lines), matching `contextFraction`'s defensive style.
- Run tests with `swift test 2>&1 | grep -E "Executed [0-9]+ tests"`; IDE/SourceKit diagnostics are permanently stale — ignore them.

---

### Task 1: Usage-event extraction from transcript JSONL

**Files:**
- Create: `Sources/ClaudeLightCore/QuotaWindow.swift`
- Test: `Tests/ClaudeLightCoreTests/QuotaWindowTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct UsageEvent: Equatable, Sendable { public let time: Date; public let tokens: Double; public let model: String?; public let source: String }`
  - `public func usageEvents(transcriptJSONL: String, source: String) -> [UsageEvent]`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ClaudeLightCore

final class QuotaWindowTests: XCTestCase {
    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    private func entry(ts: String, model: String = "claude-fable-5",
                       input: Int = 100, cacheCreate: Int = 50, cacheRead: Int = 9000,
                       output: Int = 25) -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","message":{"role":"assistant","model":"\#(model)","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheCreate),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output)}}}"#
    }

    // MARK: – usageEvents

    func test_extractsTimeTokensModel_excludingCacheReads() {
        let events = usageEvents(transcriptJSONL: entry(ts: "2026-07-05T12:00:00.000Z"), source: "a")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].tokens, 175)  // 100 + 50 + 25; 9000 cache reads excluded
        XCTAssertEqual(events[0].model, "claude-fable-5")
        XCTAssertEqual(events[0].source, "a")
        XCTAssertEqual(events[0].time, iso("2026-07-05T12:00:00.000Z"))
    }

    func test_parsesTimestampsWithAndWithoutFractionalSeconds() {
        let jsonl = entry(ts: "2026-07-05T12:00:00.123Z") + "\n" + entry(ts: "2026-07-05T12:01:00Z")
        XCTAssertEqual(usageEvents(transcriptJSONL: jsonl, source: "a").count, 2)
    }

    func test_skipsNonAssistant_corrupt_andUsagelessLines() {
        let jsonl = """
        {"type":"user","timestamp":"2026-07-05T12:00:00Z","message":{"role":"user"}}
        not json at all
        {"type":"assistant","timestamp":"2026-07-05T12:02:00Z","message":{"role":"assistant","model":"m"}}
        \(entry(ts: "2026-07-05T12:03:00Z"))
        """
        XCTAssertEqual(usageEvents(transcriptJSONL: jsonl, source: "a").count, 1)
    }

    func test_missingTimestamp_skipsLine() {
        let noTs = #"{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":5,"output_tokens":5}}}"#
        XCTAssertTrue(usageEvents(transcriptJSONL: noTs, source: "a").isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter QuotaWindowTests 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'usageEvents' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// One assistant API call's quota-relevant footprint, lifted from a
/// transcript line (#83).
public struct UsageEvent: Equatable, Sendable {
    public let time: Date
    public let tokens: Double
    public let model: String?
    public let source: String

    public init(time: Date, tokens: Double, model: String?, source: String) {
        self.time = time
        self.tokens = tokens
        self.model = model
        self.source = source
    }
}

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseTranscriptDate(_ s: String) -> Date? {
    isoFractional.date(from: s) ?? isoPlain.date(from: s)
}

/// Usage events from a transcript's JSONL. Tokens count input +
/// cache-creation + output; cache READS are excluded — they dominate raw
/// counts while being the least quota-correlated component (spec #83).
/// Defensive line-by-line parse, same stance as `contextFraction` (#96).
public func usageEvents(transcriptJSONL: String, source: String) -> [UsageEvent] {
    var events: [UsageEvent] = []
    for line in transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { continue }
        let isAssistant = (obj["type"] as? String) == "assistant"
            || (message["role"] as? String) == "assistant"
        guard isAssistant,
              let usage = message["usage"] as? [String: Any],
              let ts = obj["timestamp"] as? String,
              let time = parseTranscriptDate(ts) else { continue }
        func tokens(_ key: String) -> Double {
            (usage[key] as? NSNumber)?.doubleValue ?? 0
        }
        let total = tokens("input_tokens") + tokens("cache_creation_input_tokens")
                  + tokens("output_tokens")
        guard total > 0 else { continue }
        events.append(UsageEvent(time: time, tokens: total,
                                 model: message["model"] as? String, source: source))
    }
    return events
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter QuotaWindowTests 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/QuotaWindow.swift Tests/ClaudeLightCoreTests/QuotaWindowTests.swift
git commit -m "feat: usage-event extraction from transcript JSONL (#83)"
```

---

### Task 2: Window math and display formatting

**Files:**
- Modify: `Sources/ClaudeLightCore/QuotaWindow.swift` (append)
- Test: `Tests/ClaudeLightCoreTests/QuotaWindowTests.swift` (append)

**Interfaces:**
- Consumes: `UsageEvent` (Task 1).
- Produces:
  - `public struct QuotaWindow: Equatable, Sendable { public let start: Date; public let resetAt: Date; public let tokens: Double; public let models: [String]; public let sessions: Int }` (models are SHORT names, first-appearance order)
  - `public func quotaWindow(events: [UsageEvent], now: Date) -> QuotaWindow?`
  - `public func shortModelName(_ raw: String) -> String`
  - `public func countdownText(until reset: Date, now: Date) -> String`
  - `public func tokenText(_ tokens: Double) -> String`
  - `public func quotaTooltip(window: QuotaWindow) -> String`

- [ ] **Step 1: Write the failing tests** (append to `QuotaWindowTests`)

```swift
    // MARK: – block math

    private func ev(_ ts: String, tok: Double = 100, model: String = "claude-fable-5",
                    source: String = "s1") -> UsageEvent {
        UsageEvent(time: iso(ts), tokens: tok, model: model, source: source)
    }

    func test_singleBurst_anchorsAtFirstEntry() throws {
        let w = try XCTUnwrap(quotaWindow(
            events: [ev("2026-07-05T12:00:00Z"), ev("2026-07-05T13:30:00Z", tok: 50)],
            now: iso("2026-07-05T14:00:00Z")))
        XCTAssertEqual(w.start, iso("2026-07-05T12:00:00Z"))
        XCTAssertEqual(w.resetAt, iso("2026-07-05T17:00:00Z"))
        XCTAssertEqual(w.tokens, 150)
        XCTAssertEqual(w.sessions, 1)
    }

    func test_gapOverFiveHours_reanchors_andOnlyCurrentBlockCounts() throws {
        let w = try XCTUnwrap(quotaWindow(
            events: [ev("2026-07-05T01:00:00Z", tok: 999), ev("2026-07-05T09:00:00Z"), ev("2026-07-05T10:00:00Z")],
            now: iso("2026-07-05T10:30:00Z")))
        XCTAssertEqual(w.start, iso("2026-07-05T09:00:00Z"))
        XCTAssertEqual(w.tokens, 200)
    }

    func test_continuousOverFiveHours_blocksTileForward() throws {
        // Entries hourly 06:00–12:00, no ≥5h gap: anchor 06:00, now 12:30
        // → current block starts 11:00 (anchor + 5h); only the 11:00 and
        // 12:00 entries fall inside it.
        let hours = ["06","07","08","09","10","11","12"]
        let events = hours.map { ev("2026-07-05T\($0):00:00Z") }
        let w = try XCTUnwrap(quotaWindow(events: events, now: iso("2026-07-05T12:30:00Z")))
        XCTAssertEqual(w.start, iso("2026-07-05T11:00:00Z"))
        XCTAssertEqual(w.resetAt, iso("2026-07-05T16:00:00Z"))
        XCTAssertEqual(w.tokens, 200)  // 11:00 and 12:00 entries only
    }

    func test_newestEntryOlderThanFiveHours_isNil() {
        XCTAssertNil(quotaWindow(events: [ev("2026-07-05T01:00:00Z")],
                                 now: iso("2026-07-05T06:00:01Z")))
    }

    func test_noEvents_isNil() {
        XCTAssertNil(quotaWindow(events: [], now: iso("2026-07-05T06:00:00Z")))
    }

    func test_outOfOrderEvents_sortedBeforeGapDetection() throws {
        let w = try XCTUnwrap(quotaWindow(
            events: [ev("2026-07-05T13:00:00Z"), ev("2026-07-05T12:00:00Z")],
            now: iso("2026-07-05T13:30:00Z")))
        XCTAssertEqual(w.start, iso("2026-07-05T12:00:00Z"))
    }

    func test_modelsShortNamed_firstAppearanceOrder_distinctSources() throws {
        let w = try XCTUnwrap(quotaWindow(
            events: [ev("2026-07-05T12:00:00Z", model: "claude-fable-5", source: "a"),
                     ev("2026-07-05T12:10:00Z", model: "claude-sonnet-5", source: "b"),
                     ev("2026-07-05T12:20:00Z", model: "claude-fable-5", source: "a")],
            now: iso("2026-07-05T12:30:00Z")))
        XCTAssertEqual(w.models, ["fable-5", "sonnet-5"])
        XCTAssertEqual(w.sessions, 2)
    }

    // MARK: – formatting

    func test_shortModelName() {
        XCTAssertEqual(shortModelName("claude-fable-5"), "fable-5")
        XCTAssertEqual(shortModelName("claude-sonnet-5"), "sonnet-5")
        XCTAssertEqual(shortModelName("claude-haiku-4-5-20251001"), "haiku-4.5")
        XCTAssertEqual(shortModelName("claude-opus-4-8"), "opus-4.8")
        XCTAssertEqual(shortModelName("weird-model"), "weird-model")
    }

    func test_countdownText() {
        XCTAssertEqual(countdownText(until: iso("2026-07-05T17:00:00Z"), now: iso("2026-07-05T14:50:00Z")), "2h 10m")
        XCTAssertEqual(countdownText(until: iso("2026-07-05T17:00:00Z"), now: iso("2026-07-05T16:15:00Z")), "45m")
        XCTAssertEqual(countdownText(until: iso("2026-07-05T17:00:00Z"), now: iso("2026-07-05T16:59:30Z")), "<1m")
    }

    func test_tokenText() {
        XCTAssertEqual(tokenText(2_400_000), "2.4M")
        XCTAssertEqual(tokenText(890_000), "890k")
        XCTAssertEqual(tokenText(12_345), "12k")
        XCTAssertEqual(tokenText(950), "950")
    }

    func test_quotaTooltip_composition() {
        let w = QuotaWindow(start: iso("2026-07-05T12:00:00Z"), resetAt: iso("2026-07-05T17:00:00Z"),
                            tokens: 2_400_000, models: ["fable-5", "sonnet-5"], sessions: 3)
        let tip = quotaTooltip(window: w)
        XCTAssertTrue(tip.contains("2.4M tokens"))
        XCTAssertTrue(tip.contains("across 3 sessions"))
        XCTAssertTrue(tip.contains("models: fable-5, sonnet-5"))
        XCTAssertTrue(tip.contains("resets at"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter QuotaWindowTests 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'quotaWindow' in scope`.

- [ ] **Step 3: Write the implementation** (append to `QuotaWindow.swift`)

```swift
/// The 5-hour usage block currently in force (#83).
public struct QuotaWindow: Equatable, Sendable {
    public let start: Date
    public let resetAt: Date
    public let tokens: Double
    public let models: [String]   // short names, first-appearance order
    public let sessions: Int      // distinct transcript sources in the block

    public init(start: Date, resetAt: Date, tokens: Double, models: [String], sessions: Int) {
        self.start = start
        self.resetAt = resetAt
        self.tokens = tokens
        self.models = models
        self.sessions = sessions
    }
}

private let blockLength: TimeInterval = 5 * 3600

/// Folds usage events into the current 5h block. Anchor = first entry
/// after the most recent gap ≥ 5h (or the earliest entry); blocks tile
/// forward from the anchor; only entries inside the current block count.
/// Nil when the newest entry is older than 5h (no active window).
public func quotaWindow(events: [UsageEvent], now: Date) -> QuotaWindow? {
    let sorted = events.sorted { $0.time < $1.time }
    guard let newest = sorted.last?.time,
          now.timeIntervalSince(newest) < blockLength else { return nil }

    var anchor = sorted[0].time
    for (prev, next) in zip(sorted, sorted.dropFirst())
    where next.time.timeIntervalSince(prev.time) >= blockLength {
        anchor = next.time
    }

    let elapsed = max(0, now.timeIntervalSince(anchor))
    let start = anchor.addingTimeInterval(blockLength * (elapsed / blockLength).rounded(.down))
    let inBlock = sorted.filter { $0.time >= start && $0.time <= now }
    guard !inBlock.isEmpty else { return nil }

    var models: [String] = []
    for event in inBlock {
        guard let model = event.model.map(shortModelName), !models.contains(model) else { continue }
        models.append(model)
    }
    return QuotaWindow(start: start,
                       resetAt: start.addingTimeInterval(blockLength),
                       tokens: inBlock.reduce(0) { $0 + $1.tokens },
                       models: models,
                       sessions: Set(inBlock.map(\.source)).count)
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

/// "2h 10m" / "45m" / "<1m" until the reset.
public func countdownText(until reset: Date, now: Date) -> String {
    let minutes = Int((reset.timeIntervalSince(now) / 60).rounded(.down))
    if minutes < 1 { return "<1m" }
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h \(minutes % 60)m"
}

/// "2.4M" / "890k" / "12k" / "950".
public func tokenText(_ tokens: Double) -> String {
    if tokens >= 1_000_000 { return String(format: "%.1fM", tokens / 1_000_000) }
    if tokens >= 1_000 { return "\(Int((tokens / 1_000).rounded()))k" }
    return "\(Int(tokens.rounded()))"
}

/// Tooltip + VoiceOver line for the header countdown.
public func quotaTooltip(window: QuotaWindow) -> String {
    let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    let noun = window.sessions == 1 ? "session" : "sessions"
    return "\(tokenText(window.tokens)) tokens since \(clock.string(from: window.start)) "
         + "across \(window.sessions) \(noun) · resets at \(clock.string(from: window.resetAt)) "
         + "· models: \(window.models.joined(separator: ", "))"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter QuotaWindowTests 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: `Executed 15 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/QuotaWindow.swift Tests/ClaudeLightCoreTests/QuotaWindowTests.swift
git commit -m "feat: 5h quota-block math and display formatting (#83)"
```

---

### Task 3: Memoized transcript scanner

**Files:**
- Create: `Sources/ClaudeLightCore/TranscriptUsageScanner.swift`
- Test: `Tests/ClaudeLightCoreTests/TranscriptUsageScannerTests.swift`

**Interfaces:**
- Consumes: `usageEvents(transcriptJSONL:source:)`, `UsageEvent`, `FileMemoCache`, `FileStamp` (all existing/Task 1).
- Produces: `public final class TranscriptUsageScanner { public init(projectsDirectory: URL); public func recentEvents(now: Date) -> [UsageEvent] }` — events from transcripts with mtime within 6h, memoized per (path, mtime, size).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ClaudeLightCore

final class TranscriptUsageScannerTests: XCTestCase {
    private func makeProjects(files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-light-scan-\(UUID().uuidString)")
        for (rel, contents) in files {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func entry(ts: String) -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","message":{"role":"assistant","model":"claude-fable-5","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}"#
    }

    func test_collectsEventsAcrossProjects_sourceIsPath() throws {
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
        let root = try makeProjects(files: [
            "proj-a/s1.jsonl": entry(ts: iso),
            "proj-b/s2.jsonl": entry(ts: iso),
        ])
        let events = TranscriptUsageScanner(projectsDirectory: root).recentEvents(now: now)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.map(\.source)).count, 2)
    }

    func test_skipsStaleFiles_byMtime() throws {
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
        let root = try makeProjects(files: ["proj/old.jsonl": entry(ts: iso)])
        let old = root.appendingPathComponent("proj/old.jsonl")
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-7 * 3600)], ofItemAtPath: old.path)
        XCTAssertTrue(TranscriptUsageScanner(projectsDirectory: root).recentEvents(now: now).isEmpty)
    }

    func test_memoizes_untilStampChanges() throws {
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
        let root = try makeProjects(files: ["proj/s.jsonl": entry(ts: iso)])
        let scanner = TranscriptUsageScanner(projectsDirectory: root)
        XCTAssertEqual(scanner.recentEvents(now: now).count, 1)
        // Append a second entry: stamp changes, recompute picks it up.
        let url = root.appendingPathComponent("proj/s.jsonl")
        let appended = try String(contentsOf: url, encoding: .utf8) + "\n" + entry(ts: iso)
        try appended.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(scanner.recentEvents(now: now).count, 2)
    }

    func test_missingDirectory_returnsEmpty() {
        let scanner = TranscriptUsageScanner(
            projectsDirectory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        XCTAssertTrue(scanner.recentEvents(now: Date()).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptUsageScannerTests 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'TranscriptUsageScanner' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Walks ~/.claude/projects for transcripts touched in the last 6 hours
/// and lifts their usage events, memoized per (path, mtime, size) so the
/// panel never re-parses multi-megabyte transcripts on a tick (#83).
public final class TranscriptUsageScanner {
    /// 5h window + 1h margin: files older than this cannot contribute to
    /// the current block.
    private static let horizon: TimeInterval = 6 * 3600

    private let projectsDirectory: URL
    private let cache = FileMemoCache<[UsageEvent]>()

    public init(projectsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)) {
        self.projectsDirectory = projectsDirectory
    }

    public func recentEvents(now: Date) -> [UsageEvent] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(
            at: projectsDirectory, includingPropertiesForKeys: nil) else { return [] }

        var events: [UsageEvent] = []
        var live: Set<String> = []
        for project in projects {
            guard let files = try? fm.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(
                        forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = values.contentModificationDate,
                      now.timeIntervalSince(mtime) < Self.horizon else { continue }
                let stamp = FileStamp(mtime: mtime, size: UInt64(values.fileSize ?? 0))
                live.insert(file.path)
                events += cache.value(for: file.path, stamp: stamp) {
                    guard let jsonl = try? String(contentsOf: file, encoding: .utf8) else { return [] }
                    return usageEvents(transcriptJSONL: jsonl, source: file.path)
                }
            }
        }
        cache.evict(keeping: live)
        return events
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TranscriptUsageScannerTests 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: `Executed 4 tests, with 0 failures`. Then full suite: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1` — 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/TranscriptUsageScanner.swift Tests/ClaudeLightCoreTests/TranscriptUsageScannerTests.swift
git commit -m "feat: memoized transcript usage scanner (#83)"
```

---

### Task 4: Watcher publication and header UI

**Files:**
- Modify: `Sources/ClaudeLightApp/SessionWatcher.swift` (add scanner + published window; recompute inside `reload()`)
- Modify: `Sources/ClaudeLightApp/PanelContent.swift:45-54` (header row)

**Interfaces:**
- Consumes: `TranscriptUsageScanner`, `quotaWindow(events:now:)`, `countdownText(until:now:)`, `quotaTooltip(window:)` (Tasks 1–3).
- Produces: `SessionWatcher.quotaWindow: QuotaWindow?` (`@Published`); header renders "↻ \(countdownText(...))" when non-nil.

No unit tests — app-target glue (SessionWatcher/PanelContent are untested by the suite); the gate is the full suite as regression plus Task 5's live verification. The countdown text itself re-derives every second from the existing `TimelineView` via `countdownText(until:now:)`, already unit-tested; the window recomputes on watcher reloads (file events land on every hook write, so the scan stays fresh without its own timer).

- [ ] **Step 1: SessionWatcher** — add the property and reload hook. Near the other `private var` declarations (~line 46):

```swift
    private let usageScanner = TranscriptUsageScanner()
    @Published var quotaWindow: ClaudeLightCore.QuotaWindow?
```

At the end of `reload()` (after `self.subagentsBySession = subagentMap`, before the icon-state lines):

```swift
        // Quota window (#83): read-side scan, memoized per transcript;
        // recomputed here because every hook write lands a file event.
        self.quotaWindow = ClaudeLightCore.quotaWindow(
            events: usageScanner.recentEvents(now: Date()), now: Date())
```

- [ ] **Step 2: PanelContent header** — in `sessionList(now:)`, replace the summary HStack:

```swift
            if let summary = watcher.summary {
                HStack(spacing: 8) {
                    Circle().fill(headerColor).frame(width: 8, height: 8)
                    Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let window = watcher.quotaWindow, window.resetAt > now {
                        Text("↻ \(countdownText(until: window.resetAt, now: now))")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .help(quotaTooltip(window: window))
                            .accessibilityLabel(quotaTooltip(window: window))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                Divider()
            }
```

Note `window.resetAt > now`: a window computed at the last reload can lapse while the panel sits open; the guard hides a dead countdown between reloads.

- [ ] **Step 3: Build and run the full suite**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Build complete!`, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/SessionWatcher.swift Sources/ClaudeLightApp/PanelContent.swift
git commit -m "feat: header shows the quota-window reset countdown (#83)"
```

---

### Task 5: Live end-to-end verification and PR

**Files:** none (build + manual verification; controller-run).

**Interfaces:**
- Consumes: everything above.
- Produces: user-verified header; PR closing #83.

- [ ] **Step 1: Build, sign, swap** (standard local flow: `./scripts/package-app.sh`, codesign hook + app binaries then bundle with "Developer ID Application: Fernando Castillo (7MTZYB93KB)", quit, replace /Applications, open).

- [ ] **Step 2: Verify live** — with this session active, the header should show "↻ …" counting down within the current block; hover shows tokens/models/sessions; the countdown hides if all transcripts go quiet >5h (not practically testable live — covered by unit tests).

- [ ] **Step 3: Push, open PR** titled "feat: quota-window reset countdown in the panel header (#83)" — body covers: read-side transcript derivation (no hook changes), 5h block anchoring, cache-read exclusion rationale, no-percentage honesty stance, memoization, test counts, live verification. Closes #83.
