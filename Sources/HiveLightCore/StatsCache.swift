import Foundation

/// One day's per-model token totals from Claude Code's own stats cache
/// (`~/.claude/stats-cache.json`, `dailyModelTokens`). Claude Code recomputes
/// the cache only when its `/usage` (`/stats`) screen is opened, so it lags
/// today at best and can be weeks stale — see `recentDailyHistory`. The live
/// scanner supplies today's row (#83).
public struct DailyModelTokens: Equatable, Sendable {
    public let date: String              // "2026-07-05", as written by Claude Code
    public let tokensByModel: [String: Int]

    public init(date: String, tokensByModel: [String: Int]) {
        self.date = date
        self.tokensByModel = tokensByModel
    }
}

/// Tolerant decode: the file belongs to another program, so any surprise —
/// truncation, missing keys, non-numeric values, a future schema — degrades
/// to fewer rows or `[]`, never an error.
public func dailyModelTokens(fromJSON data: Data) -> [DailyModelTokens] {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = obj["dailyModelTokens"] as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
        guard let date = row["date"] as? String,
              let raw = row["tokensByModel"] as? [String: Any] else { return nil }
        var tokens: [String: Int] = [:]
        for (model, value) in raw {
            if let n = value as? NSNumber { tokens[model] = n.intValue }
        }
        return DailyModelTokens(date: date, tokensByModel: tokens)
    }
}

/// The cache days that really are the `days` calendar days before today,
/// oldest first. Claude Code only recomputes its stats cache when the user
/// opens `/usage` there, so the file can be weeks old — taking "the last N
/// entries" presented a six-week-old cache as recent days. Today's own entry
/// is excluded: the live scanner supplies that row. Keys are "yyyy-MM-dd", so
/// they compare correctly as strings; a malformed `todayKey` yields no rows.
public func recentDailyHistory(_ history: [DailyModelTokens], todayKey: String, days: Int) -> [DailyModelTokens] {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd"
    guard days > 0,
          let today = formatter.date(from: todayKey),
          let earliest = formatter.calendar.date(byAdding: .day, value: -days, to: today) else { return [] }
    let earliestKey = formatter.string(from: earliest)
    return history
        .filter { $0.date >= earliestKey && $0.date < todayKey }
        .sorted { $0.date < $1.date }
}
