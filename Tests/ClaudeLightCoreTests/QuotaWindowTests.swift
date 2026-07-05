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
}
