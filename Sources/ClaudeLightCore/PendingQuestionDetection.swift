import Foundation

/// Tools whose unanswered call means the session is blocked on the user.
private let blockingQuestionTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

/// True when the transcript ends with an unanswered blocking question: an
/// `AskUserQuestion` or `ExitPlanMode` tool_use with no tool_result since the
/// last real user prompt. A later user prompt supersedes stale questions left
/// by interrupted turns. Defensive/fail-safe: unparseable lines are skipped.
public func hasPendingUserQuestion(transcriptJSONL: String) -> Bool {
    var pending = Set<String>()

    for line in transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any]
        else { continue }

        // A real user prompt (typed text, not a tool_result answer) starts a new
        // turn: whatever question was left unanswered before it is stale.
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
                    pending.insert(id)
                }
            case "tool_result":
                if let id = block["tool_use_id"] as? String {
                    pending.remove(id)
                }
            default:
                continue
            }
        }
    }
    return !pending.isEmpty
}

/// User entry containing typed text (string content or a text block) — as
/// opposed to a tool_result-only entry, which is an *answer* inside a turn.
private func isRealUserPrompt(obj: [String: Any], message: [String: Any]) -> Bool {
    let isUser = (obj["type"] as? String) == "user" || (message["role"] as? String) == "user"
    guard isUser else { return false }
    if message["content"] is String { return true }
    if let blocks = message["content"] as? [[String: Any]] {
        return blocks.contains { ($0["type"] as? String) == "text" }
    }
    return false
}
