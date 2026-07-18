import Foundation

// Pure derivations for the panel UI (#86) — every string the SwiftUI layer
// renders verbatim, kept here so it is testable without a view hierarchy.

/// Card title: the project display name. The git branch renders in the
/// subtitle (#82), never here — titles ran too long with it.
public func cardTitle(for session: Session) -> String {
    displayName(for: session)
}

/// Card subtitle: what the session is blocked on or doing.
/// Precedence: error reason > detail (#80) > branch (running/idle only, #82)
/// > friendly label.
public func cardSubtitle(for session: Session, errorReason: String?) -> String? {
    switch session.status {
    case .error:
        return "API error: \(errorReason ?? "api error")"
    case .running, .idle:
        // The branch stands in for the bare status word (#82); needs-you
        // states keep their question/label — a blocked card must say why.
        return session.detail ?? session.branch ?? friendlyStatusLabel(for: session.status)
    default:
        return session.detail ?? friendlyStatusLabel(for: session.status)
    }
}

/// True when the subtitle is showing the git branch (#82) — the card
/// styles it as a ref (amber, monospaced) rather than prose.
public func subtitleShowsBranch(for session: Session) -> Bool {
    (session.status == .running || session.status == .idle)
        && session.detail == nil && session.branch != nil
}

/// Elapsed-state timer for the card's trailing edge ("12m").
public func timerText(for session: Session, now: Date) -> String {
    relativeTime(secondsAgo: now.timeIntervalSince(session.updatedAt))
}

/// Collapsed-subagents chip: "3 of 5 done" (· K failed when any failed).
public func subagentChipText(_ list: SubagentList) -> String {
    let base = "\(list.doneCount) of \(list.total) done"
    return list.failedCount > 0 ? "\(base) · \(list.failedCount) failed" : base
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

/// The owning-task line under a session row: "<subject> · done/total tasks".
/// The unit suffix keeps the count from being misread against the subagent
/// block's "X of N done" rendered directly below it.
public func taskLineText(_ summary: TaskSummary) -> String {
    "\(summary.inProgressSubject) · \(summary.doneCount)/\(summary.total) tasks"
}

/// The count-free disclosure label hiding the full completed-task history,
/// or nil when nothing has finished yet.
public func taskHistoryToggleText(_ summary: TaskSummary) -> String? {
    summary.doneSubjects.isEmpty ? nil : "earlier tasks"
}

/// Fill fraction for the task progress bar under the current-task row —
/// done over total, clamped to 0...1 (0 when the list is empty).
public func taskProgressFraction(_ summary: TaskSummary) -> Double {
    guard summary.total > 0 else { return 0 }
    return min(max(Double(summary.doneCount) / Double(summary.total), 0), 1)
}

/// The session list's scroll-frame height for a pre-layout row-weight
/// estimate, or nil at/under the threshold (the list hugs its content and
/// needs no frame). Past the threshold the height TRACKS the estimate —
/// one weight unit ≈ one plain card (~44pt) — capped at 480. The old fixed
/// 480 turned the threshold into a cliff: an estimate of 9 (~396pt of real
/// content) reserved the full 480 and rendered the difference as dead space
/// between the last card and the usage strip.
public func panelListScrollHeight(forRowWeight weight: Int) -> CGFloat? {
    guard weight > panelScrollThreshold else { return nil }
    return min(480, CGFloat(weight) * 44)
}

/// Past this estimated weight the list scrolls so the footer stays reachable.
public let panelScrollThreshold = 8

/// Which row hosts the model chip (#105). The chip rides the first row that
/// exists below the title — subtitle, then the current-task row, then the
/// subagent fan-out header — and only gets a row of its own when the card has
/// none of them. A chip-only row above other content reads as a gap.
public enum ChipHostRow: Equatable, Sendable {
    case subtitleRow, taskRow, subagentRow, ownRow
}

public func chipHostRow(hasSubtitle: Bool, hasTaskSummary: Bool,
                        hasSubagents: Bool) -> ChipHostRow {
    if hasSubtitle { return .subtitleRow }
    if hasTaskSummary { return .taskRow }
    if hasSubagents { return .subagentRow }
    return .ownRow
}
