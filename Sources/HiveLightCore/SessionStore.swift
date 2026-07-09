import Foundation

/// How long a session that stopped firing hook events is still considered live.
/// Shared by the in-memory filter (`liveSessions`) and on-disk `SessionStore.prune`.
public let defaultSessionTTL: TimeInterval = 8 * 3600

/// Sessions that have only ever seen SessionStart expire fast (#167): ghosts
/// from closed tabs and aborted launches vanish in minutes, while a real but
/// unused REPL simply reappears on its first prompt.
public let unpromptedSessionTTL: TimeInterval = 15 * 60

/// The TTL a given session deserves. Unprompted = idle and never updated
/// since birth (SessionStart stamps started_at == updated_at; any later hook
/// event moves updated_at). A nil started_at (files from older hooks) keeps
/// the generous default — never reap legacy files aggressively.
public func sessionTTL(for session: Session) -> TimeInterval {
    if session.status == .idle,
       let started = session.startedAt, started == session.updatedAt {
        return unpromptedSessionTTL
    }
    return defaultSessionTTL
}

/// One-time rename migration (#133): moves the legacy ~/.claude-light state
/// dir to its ~/.hive-light home. Only fires when the legacy dir exists and
/// the new one doesn't — never merges, never overwrites live state. Cheap
/// enough (two stats) for the hook's hot path.
public func migrateLegacyStateDir(from legacy: URL, to current: URL) {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: legacy.path, isDirectory: &isDir), isDir.boolValue,
          !fm.fileExists(atPath: current.path) else { return }
    try? fm.moveItem(at: legacy, to: current)
}

/// The default-path variant both entry points (app and hook) call at startup.
public func migrateLegacyStateDirIfNeeded() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    migrateLegacyStateDir(
        from: home.appendingPathComponent(".claude-light", isDirectory: true),
        to: home.appendingPathComponent(".hive-light", isDirectory: true)
    )
}

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

    /// Deletes session files past their TTL — decodable ones by `updatedAt`
    /// against their per-session TTL (unprompted sessions expire fast, #167),
    /// corrupt ones by file mtime against the default — so abnormally-
    /// terminated sessions don't accumulate on disk forever. Fail-safe:
    /// errors skip the file.
    public func prune(now: Date, ttl: TimeInterval = defaultSessionTTL) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for url in urls where url.pathExtension == "json" {
            let lastActivity: Date?
            let effectiveTTL: TimeInterval
            if let data = try? Data(contentsOf: url),
               let session = try? HiveLightJSON.decoder.decode(Session.self, from: data) {
                lastActivity = session.updatedAt
                effectiveTTL = Swift.min(ttl, sessionTTL(for: session))
            } else {
                lastActivity = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                effectiveTTL = ttl
            }
            if let last = lastActivity, now.timeIntervalSince(last) > effectiveTTL {
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
