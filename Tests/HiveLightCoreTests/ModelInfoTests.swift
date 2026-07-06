import XCTest
@testable import HiveLightCore

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
