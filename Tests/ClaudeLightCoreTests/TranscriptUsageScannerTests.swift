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
