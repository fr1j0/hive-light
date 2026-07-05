import Foundation

/// A session with no way to reach it: no controlling TTY and no focus deep link.
/// Typically a background/`claude -p` run (plugin jobs, consolidation). TERM_PROGRAM
/// doesn't count — child processes inherit it from the spawning shell (#64).
public func isHeadless(_ session: Session) -> Bool {
    session.tty == nil && session.focusURL == nil
}

/// Drops the rows that are pure noise: idle headless sessions. A *live* headless
/// job (running, or somehow blocked) is still worth seeing.
public func visibleSessions(_ sessions: [Session]) -> [Session] {
    sessions.filter { !($0.status == .idle && isHeadless($0)) }
}

/// Row title for a session: "project — branch" when the cwd sits on a git
/// branch (#82), with headless runs marked.
public func displayName(for session: Session) -> String {
    let base = session.branch.map { "\(session.project) — \($0)" } ?? session.project
    return isHeadless(session) ? "\(base) (background)" : base
}
