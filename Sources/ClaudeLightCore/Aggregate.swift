import Foundation

public enum AggregateLight: String, Sendable {
    case red
    case orange
    case green
}

/// Sessions still considered live. A session's timestamp only refreshes when it
/// fires a Claude Code hook event, so the TTL must be generous enough that a
/// session left open and idle for hours doesn't vanish — while still clearing
/// ghosts left by an abnormally-terminated session. Default: `defaultSessionTTL`.
public func liveSessions(_ sessions: [Session], now: Date, ttl: TimeInterval = defaultSessionTTL) -> [Session] {
    sessions.filter { now.timeIntervalSince($0.updatedAt) <= ttl }
}

/// How long a finished session lingers as a "done" row before its tombstone
/// file is removed (#54). Expiry is re-checked by the app's 30 s stale timer,
/// so rows live doneLingerWindow..+30 s in practice.
public let doneLingerWindow: TimeInterval = 120

/// The done sessions whose linger window has elapsed — the app deletes their
/// files and drops them from display. Non-done sessions never expire here.
public func expiredDoneSessions(_ sessions: [Session], now: Date,
                                linger: TimeInterval = doneLingerWindow) -> [Session] {
    sessions.filter { $0.status == .done && now.timeIntervalSince($0.updatedAt) > linger }
}

public func aggregateLight(for sessions: [Session]) -> AggregateLight {
    if sessions.contains(where: { $0.status == .waiting || $0.status == .attention || $0.status == .handoff }) { return .red }
    if sessions.contains(where: { $0.status == .running }) { return .orange }
    return .green
}

public func aggregateNeedsAttention(_ sessions: [Session]) -> Bool {
    sessions.contains { $0.status == .attention }
}
