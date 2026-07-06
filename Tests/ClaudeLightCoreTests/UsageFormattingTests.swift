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
