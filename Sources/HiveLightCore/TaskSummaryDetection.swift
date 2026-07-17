import Foundation

/// The session's task-list context: the in-progress task, the full completed
/// history (struck rows + expandable "+N earlier" disclosure), and the total.
public struct TaskSummary: Equatable, Sendable {
    public let inProgressSubject: String   // truncated to 40 chars
    public let total: Int
    /// Every completed subject, ascending completion order — the card shows
    /// the last two and hides the rest behind the history disclosure.
    public let doneSubjects: [String]

    public var doneCount: Int { doneSubjects.count }

    public init(inProgressSubject: String, total: Int, doneSubjects: [String] = []) {
        self.inProgressSubject = inProgressSubject
        self.total = total
        self.doneSubjects = doneSubjects
    }
}

/// Derives the current task list from a transcript (JSONL): the latest
/// populated `task_reminder` attachment is the base snapshot; `TaskCreate`
/// tool_results ("Task #N created successfully: <subject>") and `TaskUpdate`
/// status inputs seen after it are replayed on top, so the summary stays
/// current between reminders. Returns nil when no task state exists or no
/// task is in progress — the panel simply omits the line.
///
/// Ties: with several in-progress tasks, the one touched last (by transcript
/// order; snapshot order for untouched ones) wins. Defensive/fail-safe:
/// unparseable lines are skipped.
public func taskSummary(fromTranscript jsonl: String) -> TaskSummary? {
    struct TaskState { var subject: String; var status: String; var recency: Int }
    var tasks: [String: TaskState] = [:]
    var counter = 0
    var createUses = Set<String>()   // TaskCreate tool_use ids awaiting their result

    for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { continue }

        // A populated reminder is a full snapshot — it replaces all prior state.
        if let att = obj["attachment"] as? [String: Any],
           (att["type"] as? String) == "task_reminder",
           let items = att["content"] as? [[String: Any]], !items.isEmpty {
            tasks.removeAll()
            for item in items {
                guard let id = item["id"] as? String,
                      let subject = item["subject"] as? String,
                      let status = item["status"] as? String else { continue }
                counter += 1
                tasks[id] = TaskState(subject: subject, status: status, recency: counter)
            }
            continue
        }

        guard let message = obj["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { continue }

        for block in content {
            switch block["type"] as? String {
            case "tool_use":
                guard let name = block["name"] as? String else { continue }
                if name == "TaskCreate", let id = block["id"] as? String {
                    createUses.insert(id)
                }
                if name == "TaskUpdate",
                   let input = block["input"] as? [String: Any],
                   let taskID = input["taskId"] as? String,
                   let status = input["status"] as? String,
                   tasks[taskID] != nil {
                    if status == "deleted" {
                        tasks.removeValue(forKey: taskID)
                    } else {
                        counter += 1
                        tasks[taskID]?.status = status
                        tasks[taskID]?.recency = counter
                    }
                }
            case "tool_result":
                guard let useID = block["tool_use_id"] as? String,
                      createUses.remove(useID) != nil,
                      let text = toolResultText(block),
                      let created = parseCreateResult(text),
                      tasks[created.id] == nil else { continue }
                counter += 1
                tasks[created.id] = TaskState(subject: created.subject,
                                              status: "pending", recency: counter)
            default:
                continue
            }
        }
    }

    guard let current = tasks.values
        .filter({ $0.status == "in_progress" })
        .max(by: { $0.recency < $1.recency })
    else { return nil }
    let done = tasks.values.filter { $0.status == "completed" }
        .sorted { $0.recency < $1.recency }
    return TaskSummary(
        inProgressSubject: String(current.subject.prefix(40)),
        total: tasks.count,
        doneSubjects: done.map { String($0.subject.prefix(40)) }
    )
}

/// Parses "Task #7 created successfully: <subject>" → (id, subject).
private func parseCreateResult(_ text: String) -> (id: String, subject: String)? {
    guard text.hasPrefix("Task #"),
          let sep = text.range(of: " created successfully: ") else { return nil }
    let id = String(text[text.index(text.startIndex, offsetBy: 6)..<sep.lowerBound])
    guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
    let subject = String(text[sep.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !subject.isEmpty else { return nil }
    return (id, subject)
}

/// The plain text of a tool_result block — string content or the first text
/// block of block-array content.
func toolResultText(_ block: [String: Any]) -> String? {
    if let s = block["content"] as? String { return s }
    if let blocks = block["content"] as? [[String: Any]],
       let first = blocks.first(where: { ($0["type"] as? String) == "text" }),
       let s = first["text"] as? String { return s }
    return nil
}
