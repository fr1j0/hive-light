import Foundation

/// Single-quote-wraps a path so it survives shell word-splitting when used
/// as a Claude Code hook `command` (which is executed via a shell).
public func shellQuoted(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
