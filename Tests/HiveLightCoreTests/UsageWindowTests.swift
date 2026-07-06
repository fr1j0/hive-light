import XCTest
@testable import HiveLightCore

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

    func test_window_gapOfExactlyFiveHours_opensFreshWindow() {
        // The >= boundary: a gap of exactly windowLength opens a new window.
        let old = iso("2026-07-06T00:00:00Z")
        let fresh = iso("2026-07-06T05:00:00Z")
        let now = iso("2026-07-06T06:00:00Z")
        let w = currentUsageWindow(now: now, timestamps: [old, fresh])
        XCTAssertEqual(w?.start, fresh)
    }

    func test_window_multipleGaps_anchorsAtLastGap() {
        // Two ≥5h gaps: the anchor is the first activity after the LAST gap.
        let a = iso("2026-07-05T00:00:00Z")
        let b = iso("2026-07-05T08:00:00Z")   // gap 1 (8h)
        let c = iso("2026-07-05T20:00:00Z")   // gap 2 (12h)
        let now = iso("2026-07-05T21:00:00Z")
        let w = currentUsageWindow(now: now, timestamps: [a, b, c])
        XCTAssertEqual(w?.start, c)
        XCTAssertEqual(w?.end, c.addingTimeInterval(5 * 3600))
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
