import Foundation

/// A session with no way to reach it: no controlling TTY and no focus deep link.
/// Typically a background/`claude -p` run (plugin jobs, consolidation). TERM_PROGRAM
/// doesn't count — child processes inherit it from the spawning shell (#64).
public func isHeadless(_ session: Session) -> Bool {
    session.tty == nil && session.focusURL == nil
}

/// A session run from the system temp area — plugin jobs, statusline scripts,
/// headless sidecars. Machinery, not work: unclickable, branchless, named
/// "temp". Stable macOS roots, so this stays a pure prefix check.
public func isTempDirSession(cwd: String) -> Bool {
    let roots = ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"]
    let normalized = cwd.hasSuffix("/") ? cwd : cwd + "/"
    return roots.contains { normalized.hasPrefix($0) }
}

/// Drops the rows that are pure noise: idle headless sessions, and temp-dir
/// sessions in ANY status (they flooded the panel and the counts as
/// "temp / running" — machinery masquerading as work). A *live* headless job
/// in a real project dir is still worth seeing. This is the single choke
/// point feeding rows, counts, and the aggregate light.
public func visibleSessions(_ sessions: [Session]) -> [Session] {
    sessions.filter { !isTempDirSession(cwd: $0.cwd) && !($0.status == .idle && isHeadless($0)) }
}

/// Row title for a session: the project name, with headless runs marked.
public func displayName(for session: Session) -> String {
    isHeadless(session) ? "\(session.project) (background)" : session.project
}
