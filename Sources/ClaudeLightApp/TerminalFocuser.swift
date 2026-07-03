import AppKit
import ClaudeLightCore

/// Brings a session's hosting terminal to the front when its dropdown row is clicked.
///
/// Uses the pure `focusStrategy` decision, then executes it. Precise tab focus
/// (iTerm2 / Terminal.app) runs AppleScript that matches the captured TTY; any
/// failure — a denied Automation prompt, no matching tab — falls back to app-level
/// activation, which needs no permission. Unknown terminals are a no-op. Never throws.
enum TerminalFocuser {
    static func focus(_ session: Session) {
        switch focusStrategy(termProgram: session.termProgram, tty: session.tty,
                             focusURL: session.focusURL) {
        case .none:
            return
        case .openURL(let url):
            // Warp's warp://session/<id> deep link — permission-free precise focus.
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        case .activateApp(let bundleID):
            activate(bundleID: bundleID)
        case .terminalApp(let tty):
            runAppleScript(terminalScript(tty: tty), fallbackBundleID: "com.apple.Terminal")
        case .iterm(let tty):
            runAppleScript(itermScript(tty: tty), fallbackBundleID: "com.googlecode.iterm2")
        }
    }

    /// Permission-free: bring an app to the front (launching it if needed).
    private static func activate(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate(options: [.activateIgnoringOtherApps])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Runs an Apple event off the main thread; on any error (incl. TCC denial),
    /// falls back to plain app activation.
    private static func runAppleScript(_ source: String, fallbackBundleID: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if error != nil {
                DispatchQueue.main.async { activate(bundleID: fallbackBundleID) }
            }
        }
    }

    /// Keep only tty-device characters — the value is derived from `ps` output, but
    /// sanitize before interpolating into an AppleScript source string regardless.
    private static func sanitizedTTY(_ tty: String) -> String {
        tty.filter { $0.isLetter || $0.isNumber || $0 == "/" }
    }

    // The `activate` at the top of each script doubles as the no-match fallback:
    // if no tab's tty matches, the app still comes forward (app-level behavior).

    private static func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if (tty of t) contains "\(sanitizedTTY(tty))" then
                        set selected of t to true
                        set frontmost of w to true
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
    }

    private static func itermScript(tty: String) -> String {
        """
        tell application "iTerm"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if (tty of s) contains "\(sanitizedTTY(tty))" then
                            select w
                            select t
                            select s
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
    }
}
