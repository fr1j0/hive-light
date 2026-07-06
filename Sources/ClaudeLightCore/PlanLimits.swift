import Foundation

/// One plan-limit bucket from Anthropic's OAuth usage endpoint (#83) — the
/// same data `/usage` shows: session (5h), weekly all-models, and weekly
/// model-scoped (e.g. Fable's own cap). Percentages are REAL — they come
/// from Anthropic, not from local guessing.
public struct PlanLimit: Equatable, Sendable {
    public let kind: String        // "session" | "weekly_all" | "weekly_scoped" | future kinds
    public let label: String       // display label, derived from kind + scope
    public let percent: Int
    public let severity: String    // "normal" unless the server flags otherwise
    public let resetsAt: Date?

    public init(kind: String, label: String, percent: Int, severity: String, resetsAt: Date?) {
        self.kind = kind
        self.label = label
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
    }
}

// The endpoint writes 6-digit fractional offsets ("…T05:00:00.330921+00:00");
// ISO8601DateFormatter is unreliable past 3 digits, so a POSIX DateFormatter
// leads and ISO8601 forms are fallbacks.
private let limitsFractional: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
    return f
}()
private let limitsISOFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let limitsISOPlain = ISO8601DateFormatter()

private func parseLimitDate(_ s: String) -> Date? {
    limitsFractional.date(from: s) ?? limitsISOFractional.date(from: s) ?? limitsISOPlain.date(from: s)
}

/// Tolerant decode of the response's `limits` array — every other key is
/// ignored, any surprise degrades to fewer rows or `[]`, never an error.
/// Unknown kinds are kept (labeled by their kind) so future buckets appear
/// rather than vanish.
public func planLimits(fromJSON data: Data) -> [PlanLimit] {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = obj["limits"] as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
        guard let kind = row["kind"] as? String,
              let percent = (row["percent"] as? NSNumber)?.intValue else { return nil }
        let severity = row["severity"] as? String ?? "normal"
        let resetsAt = (row["resets_at"] as? String).flatMap(parseLimitDate)
        let scopeName = ((row["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
        let label: String
        switch kind {
        case "session": label = "Session"
        case "weekly_all": label = "Week · all"
        case "weekly_scoped": label = "Week · \(scopeName ?? "scoped")"
        default: label = kind
        }
        return PlanLimit(kind: kind, label: label, percent: percent,
                         severity: severity, resetsAt: resetsAt)
    }
}

/// Urgency for a limit bar — the context gauge's bands, so the panel speaks
/// one urgency language. A non-normal server severity outranks the threshold.
public func limitLevel(_ limit: PlanLimit) -> ContextLevel {
    switch limit.severity {
    case "normal": return contextLevel(fraction: Double(limit.percent) / 100)
    case "warning": return .warm
    default: return .hot
    }
}

private let weekdayClock: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE H:mm"
    return f
}()

/// Session limits show a countdown ("2h 36m"); weekly limits show the
/// wall-clock reset ("Wed 2:00"). Nil when the server sent no reset.
public func limitResetText(kind: String, resetsAt: Date?, now: Date) -> String? {
    guard let resetsAt else { return nil }
    return kind == "session" ? resetText(until: resetsAt, now: now)
                             : weekdayClock.string(from: resetsAt)
}
