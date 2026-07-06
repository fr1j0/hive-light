import Foundation

public struct StatusCounts: Sendable, Equatable {
    public let needYou: Int   // waiting + attention + handoff
    public let working: Int   // running
    public let idle: Int
    public let error: Int
    public init(needYou: Int, working: Int, idle: Int, error: Int) {
        self.needYou = needYou
        self.working = working
        self.idle = idle
        self.error = error
    }
}

public func statusCounts(for sessions: [Session]) -> StatusCounts {
    var needYou = 0, working = 0, idle = 0, error = 0
    for session in sessions {
        switch session.status {
        case .waiting, .attention, .handoff: needYou += 1
        case .running: working += 1
        case .idle: idle += 1
        case .error: error += 1
        }
    }
    return StatusCounts(needYou: needYou, working: working, idle: idle, error: error)
}

/// Words-and-counts summary for the dropdown header. nil = no live sessions.
public func summaryText(for counts: StatusCounts) -> String? {
    if counts.needYou == 0 && counts.working == 0 && counts.idle == 0 && counts.error == 0 { return nil }
    var parts: [String] = []
    if counts.error > 0 {
        parts.append(counts.error == 1 ? "1 error" : "\(counts.error) errors")
    }
    if counts.needYou > 0 {
        parts.append(counts.needYou == 1 ? "1 needs you" : "\(counts.needYou) need you")
    }
    if counts.working > 0 {
        parts.append("\(counts.working) working")
    }
    if parts.isEmpty { return "Idle" }   // only idle sessions
    return parts.joined(separator: " · ")
}

/// Display order for the dropdown: chronological, oldest first — the order
/// the sessions' terminal tabs were opened. Status carries NO positional
/// weight: since click-to-focus, the list is a navigation index, and indexes
/// hold still (urgency sort made rows jump mid-click). Urgency stays visible
/// through dot colors, timers, the summary, and the traffic light.
/// `startedAt` is nil for files written by older hooks. The fallback must be
/// STABLE above all (updatedAt moves on every event and would keep rows
/// shuffling): nil sorts as distant past — un-stamped sessions clump at the
/// top in fixed id order until the new hook stamps them on their next event.
public func sortedForMenu(_ sessions: [Session]) -> [Session] {
    sessions.sorted { a, b in
        let ta = a.startedAt ?? .distantPast
        let tb = b.startedAt ?? .distantPast
        if ta != tb { return ta < tb }
        return a.sessionID < b.sessionID
    }
}

/// Compact relative-age label for a session row.
public func relativeTime(secondsAgo: TimeInterval) -> String {
    let s = max(0, Int(secondsAgo))
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    if h < 24 { return "\(h)h" }
    return "\(h / 24)d"
}
