import Foundation

/// If the LAST substantive turn of a Claude Code transcript (JSONL) is a synthetic
/// "API Error: …" assistant message, returns a short normalized reason; otherwise
/// nil (recovered, or no error). Defensive/fail-safe: unparseable lines are skipped.
public func apiErrorReason(transcriptJSONL: String) -> String? {
    let lines = transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true)
    for line in lines.reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        let type = obj["type"] as? String
        let message = obj["message"] as? [String: Any]
        let role = message?["role"] as? String
        let isAssistant = type == "assistant" || role == "assistant"
        let isUser = type == "user" || role == "user"

        if isAssistant {
            if (message?["model"] as? String) == "<synthetic>" {
                // Synthetic turn: an API error (→ reason) or some other synthetic (→ nil).
                return errorReason(fromSynthetic: transcriptText(message))
            }
            if !transcriptText(message).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil                      // real assistant turn → normal
            }
            continue                            // assistant tool_use w/ no text → keep scanning
        }
        if isUser {
            if !transcriptText(message).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil                      // real user turn → recovered
            }
            continue                            // tool_result (no text) → skip
        }
        // system / hook_success / attachment / etc → skip
    }
    return nil
}

private func transcriptText(_ message: [String: Any]?) -> String {
    guard let content = message?["content"] else { return "" }
    if let s = content as? String { return s }
    if let blocks = content as? [[String: Any]] {
        return blocks.filter { ($0["type"] as? String) == "text" }
                     .compactMap { $0["text"] as? String }
                     .joined(separator: "\n")
    }
    return ""
}

/// Short display reason if `text` is an "API Error: …" message, else nil.
private func errorReason(fromSynthetic text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    guard lower.hasPrefix("api error") else { return nil }
    if lower.contains("connectionrefused") || lower.contains("unable to connect") { return "connection refused" }
    if lower.contains("connection closed") { return "connection closed" }
    let afterColon = trimmed.drop(while: { $0 != ":" }).dropFirst()
    let reason = afterColon.trimmingCharacters(in: .whitespacesAndNewlines)
    return reason.isEmpty ? "api error" : String(reason.prefix(40))
}
