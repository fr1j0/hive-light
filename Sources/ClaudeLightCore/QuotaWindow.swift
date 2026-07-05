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

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseTranscriptDate(_ s: String) -> Date? {
    isoFractional.date(from: s) ?? isoPlain.date(from: s)
}

/// Usage events from a transcript's JSONL. Tokens count input +
/// cache-creation + output; cache READS are excluded — they dominate raw
/// counts while being the least quota-correlated component (spec #83).
/// Defensive line-by-line parse, same stance as `contextFraction` (#96).
public func usageEvents(transcriptJSONL: String, source: String) -> [UsageEvent] {
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
              let time = parseTranscriptDate(ts) else { continue }
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
