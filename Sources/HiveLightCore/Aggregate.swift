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
    // Each session's own TTL applies (unprompted ones expire fast, #167);
    // an explicit ttl argument stays the cap for everything.
    sessions.filter { now.timeIntervalSince($0.updatedAt) <= Swift.min(ttl, sessionTTL(for: $0)) }
}

public func aggregateLight(for sessions: [Session]) -> AggregateLight {
    if sessions.contains(where: { $0.status == .waiting || $0.status == .attention || $0.status == .handoff }) { return .red }
    if sessions.contains(where: { $0.status == .running }) { return .orange }
    return .green
}

public func aggregateNeedsAttention(_ sessions: [Session]) -> Bool {
    sessions.contains { $0.status == .attention }
}
