import Foundation

/// One assistant API call's quota-relevant footprint, lifted from a
/// transcript line (#83).
public struct UsageEvent: Equatable, Sendable {
    public let time: Date
    public let tokens: Double
    public let model: String?
    public let source: String

    public init(time: Date, tokens: Double, model: String?, source: String) {
        self.time = time
        self.tokens = tokens
        self.model = model
        self.source = source
    }
}

/// Usage events from a transcript's JSONL. Tokens count input +
/// cache-creation + output; cache READS are excluded — they dominate raw
/// counts while being the least quota-correlated component (spec #83).
/// Defensive line-by-line parse, same stance as `contextFraction` (#96).
public func usageEvents(transcriptJSONL: String, source: String) -> [UsageEvent] {
    // Create formatters once per invocation to avoid shared mutable statics
    // that could cause races if concurrent calls extract events.
    let isoFractional = ISO8601DateFormatter()
    isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoPlain = ISO8601DateFormatter()
    isoPlain.formatOptions = [.withInternetDateTime]

    var events: [UsageEvent] = []
    for line in transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { continue }
        let isAssistant = (obj["type"] as? String) == "assistant"
            || (message["role"] as? String) == "assistant"
        guard isAssistant,
              let usage = message["usage"] as? [String: Any],
              let ts = obj["timestamp"] as? String,
              let time = isoFractional.date(from: ts) ?? isoPlain.date(from: ts) else { continue }
        func tokens(_ key: String) -> Double {
            (usage[key] as? NSNumber)?.doubleValue ?? 0
        }
        let total = tokens("input_tokens") + tokens("cache_creation_input_tokens")
                  + tokens("output_tokens")
        guard total > 0 else { continue }
        events.append(UsageEvent(time: time, tokens: total,
                                 model: message["model"] as? String, source: source))
    }
    return events
}

/// The 5-hour usage block currently in force (#83).
public struct QuotaWindow: Equatable, Sendable {
    public let start: Date
    public let resetAt: Date
    public let tokens: Double
    public let models: [String]   // short names, first-appearance order
    public let sessions: Int      // distinct transcript sources in the block

    public init(start: Date, resetAt: Date, tokens: Double, models: [String], sessions: Int) {
        self.start = start
        self.resetAt = resetAt
        self.tokens = tokens
        self.models = models
        self.sessions = sessions
    }
}

private let blockLength: TimeInterval = 5 * 3600

/// Folds usage events into the current 5h block. Anchor = first entry
/// after the most recent gap ≥ 5h (or the earliest entry); blocks tile
/// forward from the anchor; only entries inside the current block count.
/// Nil when the newest entry is older than 5h (no active window).
public func quotaWindow(events: [UsageEvent], now: Date) -> QuotaWindow? {
    // Clock skew: future-dated entries clamp to now so they can't anchor
    // a not-yet-started block and blank the gauge (spec: skew → zero).
    let sorted = events
        .map { $0.time > now ? UsageEvent(time: now, tokens: $0.tokens, model: $0.model, source: $0.source) : $0 }
        .sorted { $0.time < $1.time }
    guard let newest = sorted.last?.time,
          now.timeIntervalSince(newest) < blockLength else { return nil }

    var anchor = sorted[0].time
    for (prev, next) in zip(sorted, sorted.dropFirst())
    where next.time.timeIntervalSince(prev.time) >= blockLength {
        anchor = next.time
    }

    let elapsed = max(0, now.timeIntervalSince(anchor))
    let start = anchor.addingTimeInterval(blockLength * (elapsed / blockLength).rounded(.down))
    let inBlock = sorted.filter { $0.time >= start && $0.time <= now }
    guard !inBlock.isEmpty else { return nil }

    var models: [String] = []
    for event in inBlock {
        guard let model = event.model.map(shortModelName), !models.contains(model) else { continue }
        models.append(model)
    }
    return QuotaWindow(start: start,
                       resetAt: start.addingTimeInterval(blockLength),
                       tokens: inBlock.reduce(0) { $0 + $1.tokens },
                       models: models,
                       sessions: Set(inBlock.map(\.source)).count)
}

/// "claude-haiku-4-5-20251001" → "haiku-4.5"; "claude-fable-5" → "fable-5".
/// Strip the vendor prefix and date suffix, then join a trailing pair of
/// numeric segments with a dot. Unknown shapes pass through untouched.
public func shortModelName(_ raw: String) -> String {
    var name = raw.hasPrefix("claude-") ? String(raw.dropFirst("claude-".count)) : raw
    var parts = name.split(separator: "-").map(String.init)
    if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
        parts.removeLast()   // date suffix like 20251001
    }
    if parts.count >= 3,
       parts[parts.count - 1].allSatisfy(\.isNumber),
       parts[parts.count - 2].allSatisfy(\.isNumber) {
        let minor = parts.removeLast()
        parts[parts.count - 1] += ".\(minor)"
    }
    name = parts.joined(separator: "-")
    return name.isEmpty ? raw : name
}

/// "2h 10m" / "45m" / "<1m" until the reset.
public func countdownText(until reset: Date, now: Date) -> String {
    let minutes = Int((reset.timeIntervalSince(now) / 60).rounded(.down))
    if minutes < 1 { return "<1m" }
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h \(minutes % 60)m"
}

/// "2.4M" / "890k" / "12k" / "950".
public func tokenText(_ tokens: Double) -> String {
    let thousands = (tokens / 1_000).rounded()
    if thousands >= 1_000 { return String(format: "%.1fM", tokens / 1_000_000) }
    if tokens >= 1_000 { return "\(Int(thousands))k" }
    return "\(Int(tokens.rounded()))"
}

/// Tooltip + VoiceOver line for the header countdown.
public func quotaTooltip(window: QuotaWindow) -> String {
    let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    let noun = window.sessions == 1 ? "session" : "sessions"
    return "\(tokenText(window.tokens)) tokens since \(clock.string(from: window.start)) "
         + "across \(window.sessions) \(noun) · resets at \(clock.string(from: window.resetAt)) "
         + "· models: \(window.models.joined(separator: ", "))"
}
