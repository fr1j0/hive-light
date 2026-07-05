import XCTest
@testable import ClaudeLightCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class TranscriptUsageScannerTests: XCTestCase {
    /// True canonical path (resolving /var -> /private/var etc.). Foundation's
    /// `resolvingSymlinksInPath()` deliberately leaves well-known symlinked
    /// directories like /tmp and /var alone, but `FileManager.enumerator`
    /// reports fully-resolved paths, so tests that compare literal paths need
    /// this instead.
    private func canonical(_ url: URL) -> URL {
        guard let cstr = realpath(url.path, nil) else { return url }
        defer { free(cstr) }
        return URL(fileURLWithPath: String(cString: cstr))
    }

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
        let url = root.appendingPathComponent("proj/s.jsonl")

        // Pin the mtime to an explicit, controlled value up front. Restoring a
        // *naturally-written* mtime later via setAttributes is unreliable: APFS
        // stores nanosecond-resolution timestamps but round-tripping a Date
        // through -setAttributes(_:ofItemAtPath:) can lose precision below
        // ~microseconds, so re-applying the "same" Date can silently produce a
        // different on-disk stamp than the one first observed. Setting our own
        // Date explicitly (and only ever re-applying that exact value) sidesteps
        // the mismatch since the same lossy write is applied identically both
        // times.
        let controlledMtime = Date(timeIntervalSince1970: now.addingTimeInterval(-600).timeIntervalSince1970)
        try FileManager.default.setAttributes(
            [.modificationDate: controlledMtime], ofItemAtPath: url.path)

        let scanner = TranscriptUsageScanner(projectsDirectory: root)
        let firstEvents = scanner.recentEvents(now: now)
        XCTAssertEqual(firstEvents.count, 1)

        let originalContents = try String(contentsOf: url, encoding: .utf8)

        // Rewrite with different content of the SAME byte length (flip digits in
        // the timestamp so the parsed value differs but the file size doesn't),
        // then restore the original mtime so the (mtime, size) stamp is unchanged.
        var flipped = originalContents
        let target = "0" as Character
        let replacement = "1" as Character
        if let range = flipped.rangeOfCharacter(from: CharacterSet(charactersIn: String(target))) {
            flipped.replaceSubrange(range, with: String(replacement))
        }
        XCTAssertEqual(flipped.utf8.count, originalContents.utf8.count,
                       "rewrite must preserve byte length so the stamp is unchanged")
        XCTAssertNotEqual(flipped, originalContents)
        try flipped.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: controlledMtime], ofItemAtPath: url.path)

        // Stamp (mtime, size) is unchanged, so the cache must serve the STALE
        // (original) parsed value — including its parsed `time`, which the
        // flipped digit would change on a fresh parse — rather than re-reading
        // the rewritten bytes. Full UsageEvent equality (not just count/source)
        // is the assertion that would fail if the cache were deleted.
        let staleEvents = scanner.recentEvents(now: now)
        XCTAssertEqual(staleEvents, firstEvents)

        // Now bump the mtime forward: stamp changes, recompute picks up the
        // rewritten content plus a freshly appended second entry.
        let appended = flipped + "\n" + entry(ts: iso)
        try appended.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: controlledMtime.addingTimeInterval(1)], ofItemAtPath: url.path)
        XCTAssertEqual(scanner.recentEvents(now: now).count, 2)
    }

    func test_recursesIntoNestedSubagentDirectories() throws {
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
        let root = try makeProjects(files: [
            "root.jsonl": entry(ts: iso),
            "proj/sess/subagents/agent-1.jsonl": entry(ts: iso),
        ])
        let events = TranscriptUsageScanner(projectsDirectory: root).recentEvents(now: now)
        XCTAssertEqual(events.count, 2)
        let sources = Set(events.map(\.source))
        let resolvedRoot = canonical(root)
        XCTAssertTrue(sources.contains(resolvedRoot.appendingPathComponent("root.jsonl").path))
        XCTAssertTrue(sources.contains(
            resolvedRoot.appendingPathComponent("proj/sess/subagents/agent-1.jsonl").path))
    }

    func test_missingDirectory_returnsEmpty() {
        let scanner = TranscriptUsageScanner(
            projectsDirectory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        XCTAssertTrue(scanner.recentEvents(now: Date()).isEmpty)
    }
}
