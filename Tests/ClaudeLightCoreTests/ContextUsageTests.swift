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
        let t = assistantUsage(input: 50_000, cacheRead: 400_000, cacheCreation: 50_000)
        XCTAssertEqual(contextFraction(transcriptJSONL: t)!, 0.5, accuracy: 0.0001)
    }

    func test_missingCacheFields_countZero() {
        XCTAssertEqual(contextFraction(transcriptJSONL: assistantInputOnly(input: 250_000))!,
                       0.25, accuracy: 0.0001)
    }

    func test_lastUsageEntryWins() {
        let t = [assistantUsage(input: 100_000),
                 assistantUsage(input: 750_000)].joined(separator: "\n")
        XCTAssertEqual(contextFraction(transcriptJSONL: t)!, 0.75, accuracy: 0.0001)
    }

    func test_trailingEntriesWithoutUsage_areSkipped() {
        let t = [assistantUsage(input: 500_000),
                 assistantTextNoUsage(),
                 "not json at all"].joined(separator: "\n")
        XCTAssertEqual(contextFraction(transcriptJSONL: t)!, 0.5, accuracy: 0.0001)
    }

    func test_noUsageAnywhere_returnsNil() {
        XCTAssertNil(contextFraction(transcriptJSONL: ""))
        XCTAssertNil(contextFraction(transcriptJSONL: assistantTextNoUsage()))
    }

    func test_haikuWindow_is200k() {
        let t = assistantUsage(input: 100_000, model: "claude-haiku-4-5")
        XCTAssertEqual(contextFraction(transcriptJSONL: t)!, 0.5, accuracy: 0.0001)
    }

    func test_currentModels_useOneMillionWindow() {
        for model in ["claude-fable-5", "claude-opus-4-8", "claude-sonnet-5"] {
            let t = assistantUsage(input: 500_000, model: model)
            XCTAssertEqual(contextFraction(transcriptJSONL: t)!, 0.5, accuracy: 0.0001,
                           "window for \(model)")
        }
    }

    func test_legacyClaude3_uses200kWindow() {
        let t = assistantUsage(input: 100_000, model: "claude-3-5-sonnet-20241022")
        XCTAssertEqual(contextFraction(transcriptJSONL: t)!, 0.5, accuracy: 0.0001)
    }

    func test_clampedAtOne() {
        XCTAssertEqual(contextFraction(transcriptJSONL: assistantUsage(input: 1_500_000))!,
                       1.0, accuracy: 0.0001)
    }
}
