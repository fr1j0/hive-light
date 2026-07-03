import Foundation

/// The hosting-terminal identity captured for a session, used to focus it on click.
///
/// Built in the hook from the inherited environment plus a best-effort controlling
/// TTY. Pure and value-typed so the parsing is unit-testable; the actual env/`ps`
/// read lives in the hook's `main.swift`.
public struct TerminalContext: Equatable, Sendable {
    public let termProgram: String?
    public let tty: String?
    public let termSessionId: String?
    /// Warp's per-session deep link (`warp://session/<id>`), if the terminal
    /// provides one — opening it focuses the exact tab (#62).
    public let focusURL: String?

    public init(termProgram: String?, tty: String?, termSessionId: String?, focusURL: String? = nil) {
        self.termProgram = termProgram
        self.tty = tty
        self.termSessionId = termSessionId
        self.focusURL = focusURL
    }

    /// Parse from an environment dictionary and a resolved (best-effort) TTY.
    /// A blank TTY becomes nil. Session id prefers iTerm, then Terminal, then Warp.
    /// `WARP_FOCUS_URL` is kept only when it is a `warp://` URL — the stored value
    /// is opened on click, so nothing else may pass through.
    public init(environment: [String: String], tty: String?) {
        self.termProgram = environment["TERM_PROGRAM"]
        let trimmed = tty?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tty = (trimmed?.isEmpty == false) ? trimmed : nil
        self.termSessionId = environment["ITERM_SESSION_ID"]
            ?? environment["TERM_SESSION_ID"]
            ?? environment["WARP_SESSION_ID"]
        let rawFocusURL = environment["WARP_FOCUS_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.focusURL = (rawFocusURL?.hasPrefix("warp://") == true) ? rawFocusURL : nil
    }
}
