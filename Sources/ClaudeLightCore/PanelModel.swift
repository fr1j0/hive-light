import Foundation

// Pure derivations for the panel UI (#86) — every string the SwiftUI layer
// renders verbatim, kept here so it is testable without a view hierarchy.

/// Card title: the project display name. Branch labels join here when #82 lands.
public func cardTitle(for session: Session) -> String {
    displayName(for: session)
}

/// Card subtitle: what the session is blocked on or doing.
/// Precedence: error reason > detail (#80) > friendly label. Done rows have
/// no subtitle (they render as a single flat line).
public func cardSubtitle(for session: Session, errorReason: String?) -> String? {
    switch session.status {
    case .done:
        return nil
    case .error:
        return "API error: \(errorReason ?? "api error")"
    default:
        return session.detail ?? friendlyStatusLabel(for: session.status)
    }
}

/// Elapsed-state timer for the card's trailing edge ("12m").
public func timerText(for session: Session, now: Date) -> String {
    relativeTime(secondsAgo: now.timeIntervalSince(session.updatedAt))
}

/// Flat done-row text — same wording the menu used (#54).
public func doneRowText(for session: Session, now: Date) -> String {
    let age = relativeTime(secondsAgo: now.timeIntervalSince(session.updatedAt))
    return "\(displayName(for: session)) — done · \(age) ago"
}

/// Collapsed-subagents chip: "⑂ 3 subagents · 1 failed".
public func subagentChipText(_ list: SubagentList) -> String {
    let total = list.visible.count + list.overflowRunning
    let noun = total == 1 ? "subagent" : "subagents"
    let failed = list.visible.filter { $0.state == .failed }.count
    return failed > 0 ? "⑂ \(total) \(noun) · \(failed) failed" : "⑂ \(total) \(noun)"
}

/// VoiceOver label for a card — the wording the old menu rows carried, so
/// the panel migration doesn't regress accessibility.
public func accessibilityLabel(for session: Session) -> String {
    "\(displayName(for: session)) — \(friendlyStatusLabel(for: session.status))"
}
