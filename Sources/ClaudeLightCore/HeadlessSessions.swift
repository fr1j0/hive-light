import Foundation

/// A session with no way to reach it: no controlling TTY and no focus deep link.
/// Typically a background/`claude -p` run (plugin jobs, consolidation). TERM_PROGRAM
/// doesn't count — child processes inherit it from the spawning shell (#64).
public func isHeadless(_ session: Session) -> Bool {
    session.tty == nil && session.focusURL == nil
}

/// Drops the rows that are pure noise: headless sessions that are idle or
/// done. A *live* headless job (running, or somehow blocked) is still worth
/// seeing; a finished or parked one has nothing to reach and nothing pending.
public func visibleSessions(_ sessions: [Session]) -> [Session] {
    sessions.filter { !(($0.status == .idle || $0.status == .done) && isHeadless($0)) }
}

/// Row title for a session: the project name, with headless runs marked.
public func displayName(for session: Session) -> String {
    isHeadless(session) ? "\(session.project) (background)" : session.project
}
