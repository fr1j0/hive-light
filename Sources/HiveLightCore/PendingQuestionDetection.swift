import Foundation

/// Tools whose unanswered call means the session is blocked on the user.
private let blockingQuestionTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

/// The question text of the LAST still-unanswered blocking tool_use — an
/// `AskUserQuestion` (its input's question text) or `ExitPlanMode` (fixed
/// "plan ready for review") with no tool_result since the last real user
/// prompt. Nil when nothing is pending. A later user prompt supersedes
/// stale questions left by interrupted turns. Defensive/fail-safe:
/// unparseable lines are skipped.
public func pendingUserQuestionText(transcriptJSONL: String) -> String? {
    var pending: [(id: String, text: String)] = []

    for line in transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any]
        else { continue }

        if isRealUserPrompt(obj: obj, message: message) {
            pending.removeAll()
            continue
        }

        guard let blocks = message["content"] as? [[String: Any]] else { continue }
        for block in blocks {
            switch block["type"] as? String {
            case "tool_use":
                if let name = block["name"] as? String, blockingQuestionTools.contains(name),
                   let id = block["id"] as? String {
                    pending.removeAll { $0.id == id }
                    pending.append((id, questionText(toolName: name,
                                                     input: block["input"] as? [String: Any])))
                }
            case "tool_result":
                if let id = block["tool_use_id"] as? String {
                    pending.removeAll { $0.id == id }
                }
            default:
                continue
            }
        }
    }
    return pending.last?.text
}

/// Human-readable text for a blocking tool_use. AskUserQuestion carries its
/// question(s) in the input (both the flat `question` and the current
/// `questions` array shapes are seen in transcripts); ExitPlanMode is a
/// fixed label. Falls back to a marker so detection never loses a pending
/// question just because its text is missing.
private func questionText(toolName: String, input: [String: Any]?) -> String {
    if toolName == "ExitPlanMode" { return "plan ready for review" }
    if let q = input?["question"] as? String { return q }
    if let qs = input?["questions"] as? [[String: Any]] {
        let texts = qs.compactMap { $0["question"] as? String }
        if let first = texts.first {
            return texts.count > 1 ? "\(first) (+\(texts.count - 1) more)" : first
        }
    }
    return "question pending"
}

/// User entry containing typed text (string content or a text block) — as
/// opposed to a tool_result-only entry, which is an *answer* inside a turn.
/// Shared with SubagentDetection (failed fan-outs are superseded the same way).
func isRealUserPrompt(obj: [String: Any], message: [String: Any]) -> Bool {
    let isUser = (obj["type"] as? String) == "user" || (message["role"] as? String) == "user"
    guard isUser else { return false }
    if message["content"] is String { return true }
    if let blocks = message["content"] as? [[String: Any]] {
        return blocks.contains { ($0["type"] as? String) == "text" }
    }
    return false
}
