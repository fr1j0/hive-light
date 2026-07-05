import Foundation
import ClaudeLightCore

// A hook must never disrupt the Claude Code session: swallow all errors, always exit 0.
let input = FileHandle.standardInput.readDataToEndOfFile()

if let payload = try? ClaudeLightJSON.decoder.decode(HookPayload.self, from: input) {
    let store = SessionStore(directory: SessionStore.defaultDirectory())
    var transcriptJSONL: String? = nil
    if eventCarriesTranscript(payload.hookEventName), let path = payload.transcriptPath {
        // Lossy read: Claude Code appends concurrently and a strict UTF-8
        // decode fails wholesale on a torn tail, freezing chip/gauge (#111).
        transcriptJSONL = readTranscript(atPath: path)
    }
    // The ps-walk below is the expensive part of this hook and the terminal
    // never changes mid-session, so skip it once the session has a stored TTY —
    // applyHook keeps whatever identity was captured first (#42).
    let hasStoredTTY = store.load(sessionID: payload.sessionID)?.tty != nil
    let terminal = TerminalContext(
        environment: ProcessInfo.processInfo.environment,
        tty: hasStoredTTY ? nil : resolveControllingTTY()
    )
    try? applyHook(payload, to: store, now: Date(), transcriptJSONL: transcriptJSONL, terminal: terminal)
}

exit(0)

// MARK: - TTY resolution

/// Best-effort controlling terminal (e.g. "ttys008"). The hook's own stdio are pipes,
/// so we walk up parent PIDs (the Claude Code process and its shell) and take the first
/// real tty. Returns nil in detached/headless contexts. Bounded and fail-safe.
private func resolveControllingTTY() -> String? {
    var pid: Int32? = getpid()
    var hops = 0
    while let current = pid, hops < 6 {
        if let tty = ttyOf(pid: current) { return tty }
        pid = ppidOf(pid: current)
        hops += 1
    }
    return nil
}

private func ttyOf(pid: Int32) -> String? {
    let value = runPS(["-o", "tty=", "-p", String(pid)])
    return (value.isEmpty || value == "??" || value == "?") ? nil : value
}

private func ppidOf(pid: Int32) -> Int32? {
    Int32(runPS(["-o", "ppid=", "-p", String(pid)]))
}

private func runPS(_ args: [String]) -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/ps")
    proc.arguments = args
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return ""
    }
}
