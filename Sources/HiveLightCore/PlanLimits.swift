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
    /// The scoped model's display name (e.g. "Fable"), nil for the universal
    /// session/weekly buckets — non-nil marks a per-model row.
    public let scopeModelName: String?
    /// The scoped model's canonical id. The server WITHHOLDS it (sends null)
    /// for off-plan leftovers — a model whose promo/entitlement ended but whose
    /// weekly bucket lingers by name. nil here despite a non-nil scopeModelName
    /// is the "off-plan" tell; a genuinely entitled scoped model carries its id.
    public let scopeModelID: String?

    public init(kind: String, label: String, percent: Int, severity: String, resetsAt: Date?,
                scopeModelName: String? = nil, scopeModelID: String? = nil) {
        self.kind = kind
        self.label = label
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.scopeModelName = scopeModelName
        self.scopeModelID = scopeModelID
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
        let model = (row["scope"] as? [String: Any])?["model"] as? [String: Any]
        let scopeName = model?["display_name"] as? String
        let scopeID = model?["id"] as? String   // JSON null → nil (the off-plan tell)
        let label: String
        switch kind {
        case "session": label = "Session"
        case "weekly_all": label = "Week · all"
        case "weekly_scoped": label = "Week · \(scopeName ?? "scoped")"
        default: label = kind
        }
        return PlanLimit(kind: kind, label: label, percent: percent,
                         severity: severity, resetsAt: resetsAt,
                         scopeModelName: scopeName, scopeModelID: scopeID)
    }
}

/// A per-model (weekly_scoped) bucket — the only kind carrying a model scope.
/// These are the rows the "Per-model usage rows" setting governs; the
/// universal session/weekly buckets are never per-model.
public func isPerModelLimit(_ limit: PlanLimit) -> Bool {
    limit.scopeModelName != nil
}

/// Default visibility of a per-model bucket: HIDDEN when the server withheld
/// the model's id (an off-plan leftover, e.g. an ended Fable promo) — shown
/// when the model carries its id (a genuinely entitled scoped model). The
/// user's explicit choice, when set, overrides this.
public func perModelLimitDefaultVisible(_ limit: PlanLimit) -> Bool {
    limit.scopeModelID != nil
}

/// The limits to actually render: universal buckets always pass; a per-model
/// bucket passes when the user's override says so, else its id-based default.
/// `overrides` is keyed by model display name.
public func visibleLimits(_ limits: [PlanLimit], overrides: [String: Bool]) -> [PlanLimit] {
    limits.filter { limit in
        guard let name = limit.scopeModelName else { return true }
        return overrides[name] ?? perModelLimitDefaultVisible(limit)
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

/// Compact countdown for any bucket: "2h 36m" under a day, "3d 10h" beyond
/// (a weekday wall-clock like "Wed 2:00" clipped the row's reset column and
/// read worse at a glance — live-test verdict). `kind` kept for signature
/// stability; every kind formats the same way. Nil when the server sent no
/// reset.
public func limitResetText(kind: String, resetsAt: Date?, now: Date) -> String? {
    guard let resetsAt else { return nil }
    let remaining = resetsAt.timeIntervalSince(now)
    if remaining >= 24 * 3600 {
        let days = Int(remaining) / 86_400
        let hours = (Int(remaining) % 86_400) / 3_600
        return "\(days)d \(hours)h"
    }
    return resetText(until: resetsAt, now: now)
}
