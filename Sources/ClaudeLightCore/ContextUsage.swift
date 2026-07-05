import Foundation

/// Best-effort context-window usage from a Claude Code transcript (JSONL).
/// The LAST assistant entry carrying `message.usage` reflects the prompt
/// size of the latest API call — i.e. the session's current context
/// footprint (#96). Returns tokens/window clamped to 1.0, or nil when no
/// usage entry parses. Format is undocumented; defensive and fail-safe.
public func contextFraction(transcriptJSONL: String) -> Double? {
    let lines = transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true)
    for line in lines.reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { continue }
        let isAssistant = (obj["type"] as? String) == "assistant"
            || (message["role"] as? String) == "assistant"
        guard isAssistant, let usage = message["usage"] as? [String: Any] else { continue }
        func tokens(_ key: String) -> Double {
            (usage[key] as? NSNumber)?.doubleValue ?? 0
        }
        let total = tokens("input_tokens") + tokens("cache_read_input_tokens")
                  + tokens("cache_creation_input_tokens")
        guard total > 0 else { continue }
        return min(total / contextWindow(forModel: message["model"] as? String), 1.0)
    }
    return nil
}

/// The model's context window in tokens. Current-generation models
/// (Fable/Mythos 5, Opus 4.6+, Sonnet 4.6+/5) have 1M windows; the Haiku
/// tier, legacy claude-3, and the 4.5-era-and-older 4.x models are 200k.
/// Unknown/new ids get the 1M default — the common case going forward.
func contextWindow(forModel model: String?) -> Double {
    guard let model = model?.lowercased() else { return 1_000_000 }
    let smallWindowMarkers = ["haiku", "claude-3", "-4-5", "-4-1", "-4-0", "-4-2025"]
    if smallWindowMarkers.contains(where: model.contains) { return 200_000 }
    return 1_000_000
}
