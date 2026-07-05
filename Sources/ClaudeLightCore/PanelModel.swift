import Foundation

// Pure derivations for the panel UI (#86) — every string the SwiftUI layer
// renders verbatim, kept here so it is testable without a view hierarchy.

/// Card title: the project display name. Branch labels join here when #82 lands.
public func cardTitle(for session: Session) -> String {
    displayName(for: session)
}

/// Card subtitle: what the session is blocked on or doing.
/// Precedence: error reason > detail (#80) > friendly label.
public func cardSubtitle(for session: Session, errorReason: String?) -> String? {
    switch session.status {
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

/// Urgency bands for the context gauge (#96).
public enum ContextLevel: Equatable, Sendable {
    case ok      // < 0.75
    case warm    // 0.75 ..< 0.9 — auto-compact approaching
    case hot     // >= 0.9
}

public func contextLevel(fraction: Double) -> ContextLevel {
    if fraction >= 0.9 { return .hot }
    if fraction >= 0.75 { return .warm }
    return .ok
}

/// Lit ticks out of 5 — any measured usage lights at least one.
public func contextSegments(fraction: Double) -> Int {
    min(max(Int((fraction * 5).rounded(.up)), 1), 5)
}

/// Hover tooltip for the tick group — the one place the exact number lives.
public func contextTooltip(fraction: Double) -> String {
    "context \(Int((fraction * 100).rounded()))% used"
}
