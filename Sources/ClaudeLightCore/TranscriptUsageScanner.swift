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
