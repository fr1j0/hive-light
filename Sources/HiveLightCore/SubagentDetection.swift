import Foundation

/// One parallel subagent dispatched by a session (an `Agent`/`Task` tool_use).
public struct Subagent: Equatable, Sendable {
    public enum State: String, Sendable { case running, done, failed }
    public let id: String
    public let label: String
    public let state: State

    public init(id: String, label: String, state: State) {
        self.id = id
        self.label = label
        self.state = state
    }
}

/// The subagents to display for a session's current fan-out: every agent in
/// dispatch order plus exact batch counts. No cap — the panel shows the whole
/// list and scrolls if the card grows tall.
public struct SubagentList: Equatable, Sendable {
    public let visible: [Subagent]
    public let total: Int          // N — every dispatched agent in the batch
    public let doneCount: Int      // X in "X of N done"
    public let failedCount: Int

    public init(visible: [Subagent], total: Int, doneCount: Int, failedCount: Int) {
        self.visible = visible
        self.total = total
        self.doneCount = doneCount
        self.failedCount = failedCount
    }

    public static let empty = SubagentList(visible: [], total: 0, doneCount: 0, failedCount: 0)
    public var isEmpty: Bool { visible.isEmpty }
}

/// Pairs `Agent`/`Task` tool_use blocks with their tool_results in a parent
/// session's transcript (JSONL) to surface its parallel subagents as one batch.
///
/// State per subagent: no matching tool_result → **running**; `is_error: true`
/// → **failed**; otherwise → **done**. All three states are kept (`.done` is
/// no longer dropped) so the panel can show "X of N done" and struck-through
/// completed rows.
///
/// Background agents (the harness default for `Agent`) settle differently:
/// the tool_use gets an immediate "Async agent launched successfully" ack
/// tool_result while the agent keeps working, and real completion lands later
/// as a synthetic `<task-notification>` user message carrying the tool_use id
/// and a status. The ack keeps the agent **running**; the notification settles
/// it (`completed` → done, anything else → failed) and never counts as a
/// typed prompt.
///
/// Batch scoping: a new typed user prompt clears every *settled* agent (done
/// or failed — anything with a tool_result) so counts re-base on the current
/// batch; running agents survive the prompt (a queued message can land while
/// work is still in flight).
///
/// All agents in the batch are returned in dispatch order — the panel shows
/// the whole list. Defensive/fail-safe: unparseable lines are skipped.
public func subagents(fromTranscript jsonl: String) -> SubagentList {
    struct Pending { let id: String; let label: String }
    var order: [Pending] = []
    var seen = Set<String>()
    var errored: [String: Bool] = [:]   // tool_use_id → is_error present (i.e. settled)

    for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any]
        else { continue }

        // A new typed prompt supersedes settled (done + failed) fan-outs so the
        // count re-bases on the current batch; running ones stay (a queued
        // message can land while work is still in flight).
        if isRealUserPrompt(obj: obj, message: message) {
            let settledIDs = Set(errored.keys)
            if !settledIDs.isEmpty {
                order.removeAll { settledIDs.contains($0.id) }
                settledIDs.forEach { errored.removeValue(forKey: $0) }
            }
        }

        // A background agent's completion arrives as a string-content user
        // message, not a tool_result — settle the referenced agent from it.
        if let text = message["content"] as? String, isTaskNotification(text) {
            if let id = tagValue("tool-use-id", in: text), seen.contains(id) {
                errored[id] = tagValue("status", in: text) != "completed"
            }
            continue
        }

        guard let content = message["content"] as? [[String: Any]] else { continue }

        for block in content {
            switch block["type"] as? String {
            case "tool_use":
                guard let name = block["name"] as? String, name == "Task" || name == "Agent",
                      let id = block["id"] as? String, !seen.contains(id) else { continue }
                let desc = (block["input"] as? [String: Any])?["description"] as? String ?? ""
                seen.insert(id)
                order.append(Pending(id: id, label: String(desc.prefix(40))))
            case "tool_result":
                guard let id = block["tool_use_id"] as? String else { continue }
                if isBackgroundLaunchAck(block) { continue }   // agent still working
                errored[id] = (block["is_error"] as? Bool) ?? false
            default:
                continue
            }
        }
    }

    // Classify each agent in dispatch order; every one is shown.
    func state(of p: Pending) -> Subagent.State {
        guard let isError = errored[p.id] else { return .running }
        return isError ? .failed : .done
    }
    let visible = order.map { Subagent(id: $0.id, label: $0.label, state: state(of: $0)) }
    return SubagentList(
        visible: visible,
        total: visible.count,
        doneCount: visible.filter { $0.state == .done }.count,
        failedCount: visible.filter { $0.state == .failed }.count
    )
}

/// The immediate ack a background agent dispatch gets while the agent keeps
/// working — it must not settle the agent.
private func isBackgroundLaunchAck(_ block: [String: Any]) -> Bool {
    guard (block["is_error"] as? Bool) != true,
          let text = toolResultText(block) else { return false }
    return text.hasPrefix("Async agent launched successfully")
}

/// The text between `<tag>` and `</tag>`, or nil.
private func tagValue(_ tag: String, in text: String) -> String? {
    guard let open = text.range(of: "<\(tag)>"),
          let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex)
    else { return nil }
    return String(text[open.upperBound..<close.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
