import Foundation

/// Reads the tail (last `maxBytes`; the whole file if smaller) of a Claude
/// Code transcript for the hook's Stop-path scans (#96/#105) and the app's
/// reload scans (#106). Two truncation edges are expected and safe, because
/// every consumer splits per line and defensively skips unparseable lines:
/// - torn tail: Claude Code appends concurrently, and a strict UTF-8 decode
///   would fail wholesale on a torn multibyte sequence, silently freezing
///   the model chip and context gauge (#111) — decode lossily so only the
///   torn partial line degrades to replacement characters
/// - torn head: the byte cap can slice mid-line, leaving a partial first line.
///
/// nil when the file can't be read (or is empty — no lines to scan either way).
public func readTranscript(atPath path: String, maxBytes: Int = 64 * 1024) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    guard let end = try? handle.seekToEnd() else { return nil }
    let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
    try? handle.seek(toOffset: start)
    guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
    return String(decoding: data, as: UTF8.self)
}
