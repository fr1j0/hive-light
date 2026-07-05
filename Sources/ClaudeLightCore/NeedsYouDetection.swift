import Foundation

/// True when the session is blocked on the user (the red-lamp statuses).
public func needsYou(_ status: SessionStatus) -> Bool {
    switch status {
    case .waiting, .attention, .handoff, .error: return true
    case .running, .idle: return false
    }
}

/// Sessions that entered a needs-you state since the previous snapshot —
/// either transitioning from a non-blocked status or appearing already blocked.
/// Moving between two needs-you states does not count. Order follows `current`.
public func newlyNeedingYou(previous: [String: SessionStatus], current: [Session]) -> [Session] {
    current.filter { session in
        guard needsYou(session.status) else { return false }
        guard let before = previous[session.sessionID] else { return true }
        return !needsYou(before)
    }
}

/// Human wording for a status, shared by menu rows and notification bodies.
public func friendlyStatusLabel(for status: SessionStatus) -> String {
    switch status {
    case .running: return "running"
    case .waiting: return "waiting for permission"
    case .attention: return "awaiting your reply"
    case .handoff: return "review requested"
    case .idle: return "idle"
    case .error: return "API error"
    }
}
