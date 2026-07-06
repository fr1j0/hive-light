import Foundation

/// A file's identity for change detection: modification time plus byte size.
public struct FileStamp: Equatable, Sendable {
    public let mtime: Date
    public let size: UInt64

    public init(mtime: Date, size: UInt64) {
        self.mtime = mtime
        self.size = size
    }
}

/// Memoizes a value derived from a file's contents, keyed by path and invalidated
/// when the file's stamp changes. Lets the watcher skip re-reading multi-megabyte
/// transcripts on every reload when the file hasn't moved (#42).
public final class FileMemoCache<Value> {
    private var entries: [String: (stamp: FileStamp, value: Value)] = [:]

    public init() {}

    public func value(for path: String, stamp: FileStamp, compute: () -> Value) -> Value {
        if let entry = entries[path], entry.stamp == stamp {
            return entry.value
        }
        let value = compute()
        entries[path] = (stamp, value)
        return value
    }

    /// Drops entries for files no longer of interest (e.g. ended sessions).
    public func evict(keeping paths: Set<String>) {
        entries = entries.filter { paths.contains($0.key) }
    }
}
