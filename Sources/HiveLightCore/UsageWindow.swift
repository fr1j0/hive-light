import Foundation

/// One assistant turn's token spend: when, which model, in+out tokens.
/// Cache read/creation tokens are deliberately excluded — this matches the
/// basis Claude Code's own stats cache uses, so live and historical numbers
/// agree (#83).
public struct UsageEntry: Equatable, Sendable {
    public let timestamp: Date
    public let model: String
    public let tokens: Int

    public init(timestamp: Date, model: String, tokens: Int) {
        self.timestamp = timestamp
        self.model = model
        self.tokens = tokens
    }
}

/// A model's summed burn over some range, for display.
public struct ModelBurn: Equatable, Sendable {
    public let model: String
    public let tokens: Int

    public init(model: String, tokens: Int) {
        self.model = model
        self.tokens = tokens
    }
}

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain = ISO8601DateFormatter()

private func parseTimestamp(_ s: String) -> Date? {
    isoFractional.date(from: s) ?? isoPlain.date(from: s)
}

/// Per-entry token spend from a transcript (JSONL). Streaming writes several
/// lines per assistant message with cumulative usage under one message id —
/// dedupe by id, last occurrence wins. Same defensive scan idiom as
/// `contextFraction` (#96): unparseable lines are skipped, never crash.
public func usageEntries(transcriptJSONL: String) -> [UsageEntry] {
    var byID: [String: UsageEntry] = [:]
    var anonymous: [UsageEntry] = []
    for line in transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { continue }
        let isAssistant = (obj["type"] as? String) == "assistant"
            || (message["role"] as? String) == "assistant"
        guard isAssistant,
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, !model.isEmpty,
              let ts = obj["timestamp"] as? String,
              let date = parseTimestamp(ts) else { continue }
        let tokens = ((usage["input_tokens"] as? NSNumber)?.intValue ?? 0)
                   + ((usage["output_tokens"] as? NSNumber)?.intValue ?? 0)
        guard tokens > 0 else { continue }
        let entry = UsageEntry(timestamp: date, model: model, tokens: tokens)
        if let id = message["id"] as? String {
            byID[id] = entry   // streaming: last occurrence carries final counts
        } else {
            anonymous.append(entry)
        }
    }
    return (Array(byID.values) + anonymous).sorted { $0.timestamp < $1.timestamp }
}

/// Gap-aware 5h tiling (#83): a window opens at the first activity after the
/// previous window closes. Anchored at the first activity after the last
/// ≥`windowLength` idle gap — any window containing the gap's earlier side has
/// closed before its later side, so the later side opens fresh. Returns the
/// window containing `now`, or nil when the last window has already closed.
public func currentUsageWindow(now: Date, timestamps: [Date],
                               windowLength: TimeInterval = 5 * 3600) -> (start: Date, end: Date)? {
    let past = timestamps.filter { $0 <= now }.sorted()
    guard var start = past.first else { return nil }
    for i in 1..<max(past.count, 1) where past[i].timeIntervalSince(past[i - 1]) >= windowLength {
        start = past[i]
    }
    while now >= start.addingTimeInterval(windowLength) {
        let close = start.addingTimeInterval(windowLength)
        guard let next = past.first(where: { $0 >= close }) else { return nil }
        start = next
    }
    return (start, start.addingTimeInterval(windowLength))
}

/// Per-model sums over [start, end), largest burn first (ties by name for
/// deterministic display).
public func usageByModel(_ entries: [UsageEntry], from start: Date, to end: Date) -> [ModelBurn] {
    var sums: [String: Int] = [:]
    for e in entries where e.timestamp >= start && e.timestamp < end {
        sums[e.model, default: 0] += e.tokens
    }
    return sums.map { ModelBurn(model: $0.key, tokens: $0.value) }
        .sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.model < $1.model }
}
