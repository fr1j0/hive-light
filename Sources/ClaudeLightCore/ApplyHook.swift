import Foundation

public func applyHook(_ payload: HookPayload, to store: SessionStore, now: Date,
                      transcriptJSONL: String? = nil, terminal: TerminalContext? = nil) throws {
    switch action(for: payload, transcriptJSONL: transcriptJSONL) {
    case .ignore:
        return
    case .delete:
        try store.delete(sessionID: payload.sessionID)
    case .set(let status, let detail):
        let cwd = payload.cwd ?? ""
        // Terminal identity never changes mid-session: whatever was captured
        // first wins, so later events can skip the expensive TTY resolution (#42).
        let existing = store.load(sessionID: payload.sessionID)
        let session = Session(
            sessionID: payload.sessionID,
            status: status,
            project: projectName(forCwd: cwd),
            cwd: cwd,
            updatedAt: now,
            transcriptPath: payload.transcriptPath,
            termProgram: existing?.termProgram ?? terminal?.termProgram,
            tty: existing?.tty ?? terminal?.tty,
            termSessionId: existing?.termSessionId ?? terminal?.termSessionId,
            focusURL: existing?.focusURL ?? terminal?.focusURL,
            // Belt-and-braces: the ≤140 cap holds even if a future action path forgets it.
            detail: detail.map(truncatedDetail),
            // Context usage refreshes only when a transcript is in hand (the
            // Stop path); other events keep the last measurement (#96).
            contextFraction: transcriptJSONL.flatMap { contextFraction(transcriptJSONL: $0) }
                ?? existing?.contextFraction,
            // Branch refreshes whenever the event carries a cwd — a nil read
            // (detached HEAD, repo gone) clears the label. cwd-less events
            // keep the last value, like contextFraction (#82).
            branch: payload.cwd != nil ? gitBranch(forCwd: cwd) : existing?.branch,
            // Model refreshes with the same cadence as contextFraction:
            // only a transcript-bearing event re-reads it (#105).
            model: transcriptJSONL.flatMap { lastModelID(transcriptJSONL: $0) }
                ?? existing?.model,
            // Set once at the session's first event, sticky forever — the
            // panel's stable sort key (terminal-tab order).
            startedAt: existing?.startedAt ?? now,
            // Grouping identity: refreshes with cwd like branch; cwd-less
            // events keep the last value.
            repoRoot: payload.cwd != nil ? gitRepoRoot(forCwd: cwd) : existing?.repoRoot
        )
        try store.write(session)
    }
}

/// Display name for a session, derived from its working directory's basename.
/// Sessions rooted in a system temp directory (e.g. macOS `$TMPDIR` at
/// `/var/folders/.../T`, or `/tmp`) are labeled "temp" rather than the bare,
/// confusing folder name (which for `$TMPDIR` is just "T").
public func projectName(forCwd cwd: String) -> String {
    if cwd.isEmpty { return "unknown" }
    if isTemporaryPath(cwd) { return "temp" }
    return URL(fileURLWithPath: cwd).lastPathComponent
}

/// True when `cwd` lives inside a system temporary directory.
func isTemporaryPath(_ cwd: String) -> Bool {
    var path = cwd
    while path.count > 1 && path.hasSuffix("/") { path.removeLast() }

    if path == "/tmp" || path.hasPrefix("/tmp/") { return true }
    if path == "/private/tmp" || path.hasPrefix("/private/tmp/") { return true }

    // macOS per-user temp lives under /var/folders/<x>/<y>/T[/...] (also via /private).
    // The sibling "C" directory holds caches, not temp, so match the "T" component only.
    if path.contains("/var/folders/") {
        let comps = path.split(separator: "/").map(String.init)
        if let folders = comps.firstIndex(of: "folders") {
            return comps[(folders + 1)...].contains("T")
        }
    }
    return false
}
