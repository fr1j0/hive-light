import Foundation

/// The model id of the LAST assistant entry in a transcript (#105) —
/// the model the session is currently running. Same defensive reverse
/// scan as `contextFraction` (#96); nil when no assistant entry carries
/// a model.
public func lastModelID(transcriptJSONL: String) -> String? {
    let lines = transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true)
    for line in lines.reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { continue }
        let isAssistant = (obj["type"] as? String) == "assistant"
            || (message["role"] as? String) == "assistant"
        guard isAssistant, let model = message["model"] as? String, !model.isEmpty else { continue }
        return model
    }
    return nil
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
