import Foundation

/// One day's per-model token totals from Claude Code's own stats cache
/// (`~/.claude/stats-cache.json`, `dailyModelTokens`). The cache is computed
/// by Claude Code on its own cadence and typically lags today — the live
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
