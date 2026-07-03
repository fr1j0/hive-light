import Foundation

public func applyHook(_ payload: HookPayload, to store: SessionStore, now: Date,
                      transcriptJSONL: String? = nil, terminal: TerminalContext? = nil) throws {
    switch action(for: payload, transcriptJSONL: transcriptJSONL) {
    case .ignore:
        return
    case .delete:
        try store.delete(sessionID: payload.sessionID)
    case .set(let status):
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
            focusURL: existing?.focusURL ?? terminal?.focusURL
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
