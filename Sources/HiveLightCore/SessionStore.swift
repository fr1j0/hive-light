import Foundation

/// How long a session that stopped firing hook events is still considered live.
/// Shared by the in-memory filter (`liveSessions`) and on-disk `SessionStore.prune`.
public let defaultSessionTTL: TimeInterval = 8 * 3600

public struct SessionStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hive-light", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public func fileURL(for sessionID: String) -> URL {
        directory.appendingPathComponent("\(sessionID).json")
    }

    public func write(_ session: Session) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try HiveLightJSON.encoder.encode(session)
        try data.write(to: fileURL(for: session.sessionID), options: .atomic)
    }

    public func delete(sessionID: String) throws {
        let url = fileURL(for: sessionID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// The stored session, or nil when missing or undecodable. Fail-safe.
    public func load(sessionID: String) -> Session? {
        guard let data = try? Data(contentsOf: fileURL(for: sessionID)) else { return nil }
        return try? HiveLightJSON.decoder.decode(Session.self, from: data)
    }

    /// Deletes session files past the TTL — decodable ones by their `updatedAt`,
    /// corrupt ones by file mtime — so abnormally-terminated sessions don't
    /// accumulate on disk forever. Fail-safe: errors skip the file.
    public func prune(now: Date, ttl: TimeInterval = defaultSessionTTL) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for url in urls where url.pathExtension == "json" {
            let lastActivity: Date?
            if let data = try? Data(contentsOf: url),
               let session = try? HiveLightJSON.decoder.decode(Session.self, from: data) {
                lastActivity = session.updatedAt
            } else {
                lastActivity = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
            }
            if let last = lastActivity, now.timeIntervalSince(last) > ttl {
                try? fm.removeItem(at: url)
            }
        }
    }

    public func loadAll() throws -> [Session] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? HiveLightJSON.decoder.decode(Session.self, from: data)
        }
    }
}
