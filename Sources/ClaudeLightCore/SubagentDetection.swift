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

/// The subagents to display for a session's current fan-out: capped display
/// rows plus exact batch counts and the per-kind overflow hidden by the cap.
public struct SubagentList: Equatable, Sendable {
    public let visible: [Subagent]
    public let total: Int          // N — every dispatched agent in the batch
    public let doneCount: Int      // X in "X of N done" — exact, cap-independent
    public let failedCount: Int    // exact, cap-independent
    public let overflowRunning: Int
    public let overflowDone: Int

    public init(visible: [Subagent], total: Int, doneCount: Int,
                failedCount: Int, overflowRunning: Int, overflowDone: Int) {
        self.visible = visible
        self.total = total
        self.doneCount = doneCount
        self.failedCount = failedCount
        self.overflowRunning = overflowRunning
        self.overflowDone = overflowDone
    }

    public static let empty = SubagentList(visible: [], total: 0, doneCount: 0,
                                           failedCount: 0, overflowRunning: 0, overflowDone: 0)
    public var isEmpty: Bool {
        visible.isEmpty && overflowRunning == 0 && overflowDone == 0
    }
}

/// Pairs `Agent`/`Task` tool_use blocks with their tool_results in a parent
/// session's transcript (JSONL) to surface its parallel subagents as one batch.
///
/// State per subagent: no matching tool_result → **running**; `is_error: true`
/// → **failed**; otherwise → **done**. All three states are kept (`.done` is
/// no longer dropped) so the panel can show "X of N done" and struck-through
/// completed rows.
///
/// Batch scoping: a new typed user prompt clears every *settled* agent (done
/// or failed — anything with a tool_result) so counts re-base on the current
/// batch; running agents survive the prompt (a queued message can land while
/// work is still in flight).
///
/// Row cap: failed subagents are always shown and never dropped, even past
/// `maxRows`. Running subagents fill the remaining budget; done subagents
/// fill whatever's left after that. Overflow past the cap is reported per
/// kind as `overflowRunning`/`overflowDone`. Defensive/fail-safe: unparseable
/// lines are skipped.
public func subagents(fromTranscript jsonl: String, maxRows: Int = 6) -> SubagentList {
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
                errored[id] = (block["is_error"] as? Bool) ?? false
            default:
                continue
            }
        }
    }

    // Classify in dispatch order.
    func state(of p: Pending) -> Subagent.State {
        guard let isError = errored[p.id] else { return .running }
        return isError ? .failed : .done
    }
    let total = order.count
    let doneCount = order.filter { state(of: $0) == .done }.count
    let failedCount = order.filter { state(of: $0) == .failed }.count

    // Row-cap budget: failed always shown (never dropped, even past the cap);
    // running fill the remaining budget; done fill what's left. Counts are
    // decided in a pre-pass so the done budget is correct regardless of how
    // running/done interleave in dispatch order; a second pass emits the kept
    // rows in dispatch order.
    let runningCount = total - doneCount - failedCount
    // Failed agents are never dropped and consume budget first; if failures alone
    // meet or exceed maxRows, running work is pushed entirely into the overflow
    // line. Rare (6+ concurrent failures) and acceptable — failures are the signal.
    let runningBudget = max(0, maxRows - failedCount)
    let runningShown = min(runningCount, runningBudget)
    let doneBudget = max(0, maxRows - failedCount - runningShown)
    let doneShown = min(doneCount, doneBudget)

    var runningPlaced = 0
    var donePlaced = 0
    var visible: [Subagent] = []
    for p in order {
        switch state(of: p) {
        case .failed:
            visible.append(Subagent(id: p.id, label: p.label, state: .failed))
        case .running:
            if runningPlaced < runningShown {
                visible.append(Subagent(id: p.id, label: p.label, state: .running))
                runningPlaced += 1
            }
        case .done:
            if donePlaced < doneShown {
                visible.append(Subagent(id: p.id, label: p.label, state: .done))
                donePlaced += 1
            }
        }
    }
    return SubagentList(
        visible: visible,
        total: total,
        doneCount: doneCount,
        failedCount: failedCount,
        overflowRunning: runningCount - runningShown,
        overflowDone: doneCount - doneShown
    )
}
