import XCTest
@testable import ClaudeLightCore

final class TranscriptReadingTests: XCTestCase {
    private func writeFixture(_ bytes: Data) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptReadingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("transcript.jsonl")
        try bytes.write(to: file)
        return file.path
    }

    /// Claude Code appends to the transcript while the Stop hook reads it. A
    /// read that catches a torn multibyte UTF-8 sequence at the tail must not
    /// lose the whole file (#111): complete lines stay parseable and the torn
    /// partial line is skipped by the per-line defensive scans.
    func test_tornUTF8Tail_keepsCompleteLines() throws {
        var bytes = Data(#"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":47929}}}"#.utf8)
        bytes.append(Data("\n".utf8))
        bytes.append(Data(#"{"type":"user","partial":"caf"#.utf8))
        bytes.append(Data([0xC3])) // first byte of a 2-byte UTF-8 char, torn mid-append

        let path = try writeFixture(bytes)
        let jsonl = try XCTUnwrap(readTranscript(atPath: path))
        XCTAssertEqual(lastModelID(transcriptJSONL: jsonl), "claude-opus-4-8")
        XCTAssertEqual(contextFraction(transcriptJSONL: jsonl), 47_929.0 / 1_000_000.0)
    }

    func test_wellFormedFile_readsVerbatim() throws {
        let content = #"{"type":"assistant","message":{"role":"assistant","model":"claude-fable-5"}}"#
        let path = try writeFixture(Data(content.utf8))
        XCTAssertEqual(readTranscript(atPath: path), content)
    }

    func test_missingFile_isNil() {
        XCTAssertNil(readTranscript(atPath: "/nonexistent/no-such-transcript.jsonl"))
    }
}
