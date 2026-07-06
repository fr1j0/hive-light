import Foundation
import Combine
import HiveLightCore

/// What the usage surfaces render: current-window burn + reset, today's burn
/// (the history view's live row — the stats cache lags a day), and the cached
/// daily history.
struct UsageSnapshot: Equatable {
    var windowBurn: [ModelBurn] = []
    var windowEnd: Date?
    var todayBurn: [ModelBurn] = []
    var dailyHistory: [DailyModelTokens] = []
}

/// Scans recently-modified transcripts for per-model window burn (#83).
/// The scan NEVER runs on the main actor — the archived quota-window attempt
/// died on a ~200ms synchronous parse per reload. Work happens in a detached
/// task over a stamp-memoized per-file cache; only the published snapshot
/// assignment touches main.
@MainActor
final class UsageScanner: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()

    private var scanning = false
    private var lastScan = Date.distantPast
    private let cache = FileMemoCache<[UsageEntry]>()

    /// How far back transcript mtimes are considered. The window anchor needs
    /// history back to the last ≥5h idle gap; 24h reaches it in practice
    /// (if no gap exists in 24h, the anchor approximates at the oldest
    /// scanned activity).
    nonisolated static let lookback: TimeInterval = 24 * 3600
    nonisolated static let maxTailBytes = 4 * 1024 * 1024
    nonisolated static let minScanInterval: TimeInterval = 30

    func refresh(force: Bool = false) {
        guard !scanning,
              force || Date().timeIntervalSince(lastScan) >= Self.minScanInterval else { return }
        scanning = true
        let cache = self.cache   // bind before detaching (CI strict concurrency)
        // Sendable-safety: `cache` is a non-Sendable class, but access is
        // serialized — the `scanning` flag admits one scan at a time and
        // the await establishes happens-before between scans.
        Task { [weak self] in
            let snap = await Task.detached(priority: .utility) {
                Self.scan(cache: cache)
            }.value
            self?.snapshot = snap
            self?.scanning = false
            self?.lastScan = Date()
        }
    }

    // MARK: - Off-main scan (static: no self capture in the detached task)

    /// The cache is touched only here, and scans are serialized by the
    /// `scanning` flag — no concurrent mutation.
    nonisolated static func scan(cache: FileMemoCache<[UsageEntry]>, now: Date = Date()) -> UsageSnapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent(".claude/projects")
        let paths = transcriptPaths(root: root, since: now.addingTimeInterval(-lookback))

        var entries: [UsageEntry] = []
        for path in paths {
            guard let stamp = stamp(path: path) else { continue }
            entries += cache.value(for: path, stamp: stamp) {
                tailText(path: path, maxBytes: maxTailBytes)
                    .map(usageEntries(transcriptJSONL:)) ?? []
            }
        }
        cache.evict(keeping: Set(paths))
        entries.sort { $0.timestamp < $1.timestamp }

        var snap = UsageSnapshot()
        if let window = currentUsageWindow(now: now, timestamps: entries.map(\.timestamp)) {
            snap.windowBurn = usageByModel(entries, from: window.start, to: window.end)
            snap.windowEnd = window.end
        }
        let dayStart = Calendar.current.startOfDay(for: now)
        snap.todayBurn = usageByModel(entries, from: dayStart, to: now.addingTimeInterval(1))

        let cacheURL = home.appendingPathComponent(".claude/stats-cache.json")
        if let data = try? Data(contentsOf: cacheURL) {
            snap.dailyHistory = dailyModelTokens(fromJSON: data)
        }
        return snap
    }

    nonisolated static func transcriptPaths(root: URL, since: Date) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var out: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let mtime = values?.contentModificationDate, mtime >= since {
                out.append(url.path)
            }
        }
        return out
    }

    nonisolated static func stamp(path: String) -> FileStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? NSNumber else { return nil }
        return FileStamp(mtime: mtime, size: size.uint64Value)
    }

    /// Bounded tail read, lossy-decoded — a live transcript's tail can be torn
    /// mid-UTF-8 (#111) and its first line mid-JSON; `usageEntries` skips both.
    nonisolated static func tailText(path: String, maxBytes: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
