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
public enum SessionOrder: String, Sendable {
    case opened    // pure chronological — terminal-tab order
    case project   // repo blocks (by first-opened), chronological within
}

public func sortedForMenu(_ sessions: [Session],
                          order: SessionOrder = .project) -> [Session] {
    func startKey(_ s: Session) -> (Date, String) {
        (s.startedAt ?? .distantPast, s.sessionID)
    }
    guard order == .project else {
        return sessions.sorted { startKey($0) < startKey($1) }
    }
    // Group identity: the repo root (worktrees/subdirs unify with their main
    // checkout), else the literal cwd. Never the NAME — basename collisions
    // must not merge unrelated projects. Blocks hold the position of their
    // earliest session; chronological within. Every comparison is a total
    // order — no reliance on sort stability.
    func groupKey(_ s: Session) -> String { s.repoRoot ?? s.cwd }
    var blockStart: [String: (Date, String)] = [:]
    for s in sessions {
        let k = groupKey(s), v = startKey(s)
        if let existing = blockStart[k] {
            if v < existing { blockStart[k] = v }
        } else {
            blockStart[k] = v
        }
    }
    return sessions.sorted { a, b in
        let ka = groupKey(a), kb = groupKey(b)
        if ka != kb { return blockStart[ka]! < blockStart[kb]! }
        return startKey(a) < startKey(b)
    }
}

/// Consecutive runs of the (already grouped-sorted) list sharing a repo
/// identity — the panel's render blocks. Blocks of 2+ get the group
/// treatment (header + rail + branch-led cards); singletons render classic.
public func sessionBlocks(_ sessions: [Session]) -> [[Session]] {
    var blocks: [[Session]] = []
    for session in sessions {
        let key = session.repoRoot ?? session.cwd
        if let last = blocks.last?.first, (last.repoRoot ?? last.cwd) == key {
            blocks[blocks.count - 1].append(session)
        } else {
            blocks.append([session])
        }
    }
    return blocks
}

/// Header for a 2+ block: the repo directory's name (stable across the
/// block, unlike per-session project names — a worktree session's folder
/// name must not label the whole repo).
public func blockTitle(_ block: [Session]) -> String {
    guard let first = block.first else { return "" }
    let root = first.repoRoot ?? first.cwd
    return root.split(separator: "/").last.map(String.init) ?? first.project
}

/// Card title inside a 2+ block: the branch is what distinguishes siblings
/// (the header owns the repo name). Non-repo/branchless sessions fall back
/// to the project name; sessions living outside the repo root (worktrees,
/// subdirectories) carry a dim locator suffix.
public func groupedCardTitle(for session: Session) -> String {
    var title = session.branch ?? session.project
    if let root = session.repoRoot, root != session.cwd,
       let base = session.cwd.split(separator: "/").last {
        title += " · \(base)"
    }
    return title
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
