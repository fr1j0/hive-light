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
        let events = usageEvents(transcriptJSONL: jsonl, source: "a")
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].time, iso("2026-07-05T12:01:00Z"))
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

    func test_futureTimestamps_clampToNow_windowSurvives() throws {
        let w = try XCTUnwrap(quotaWindow(
            events: [ev("2026-07-05T12:00:00Z"), ev("2026-07-05T12:45:00Z")],
            now: iso("2026-07-05T12:30:00Z")))
        XCTAssertEqual(w.start, iso("2026-07-05T12:00:00Z"))
        XCTAssertEqual(w.tokens, 200)  // the future entry clamps in, not out
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

    func test_tokenText_boundaryPromotesToM() {
        XCTAssertEqual(tokenText(999_500), "1.0M")
        XCTAssertEqual(tokenText(999_499), "999k")
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
}
