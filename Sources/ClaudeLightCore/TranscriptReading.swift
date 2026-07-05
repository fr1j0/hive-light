import Foundation

/// Reads a Claude Code transcript for the Stop-path scans (#96/#105).
/// Claude Code appends to the file concurrently, so a strict UTF-8 read can
/// catch a torn multibyte sequence at the tail and fail wholesale — which
/// silently froze the model chip and context gauge until the next Stop
/// (#111). Decode lossily instead: only the torn partial line degrades to
/// replacement characters, and the per-line defensive JSON scans already
/// skip it. nil only when the file itself can't be read.
public func readTranscript(atPath path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return String(decoding: data, as: UTF8.self)
}
