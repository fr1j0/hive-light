import Foundation

/// "1.4M" / "320k" / "980" — one decimal at M scale, none below.
public func tokenText(_ tokens: Int) -> String {
    if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
    if tokens >= 1_000 { return "\(Int((Double(tokens) / 1_000).rounded()))k" }
    return "\(tokens)"
}

/// Countdown to the window close: "1h 40m" / "40m" / "<1m".
public func resetText(until end: Date, now: Date) -> String {
    let remaining = end.timeIntervalSince(now)
    guard remaining >= 60 else { return "<1m" }
    let h = Int(remaining) / 3600
    let m = (Int(remaining) % 3600) / 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

/// Fixed categorical slot per model family (#83) — the palette is assigned
/// by entity and never cycled. Substring family match, like `shortModelName`,
/// so dated and bare ids both resolve.
public enum ModelColorSlot: Equatable, Sendable { case fable, opus, sonnet, haiku, other }

public func modelColorSlot(_ modelID: String) -> ModelColorSlot {
    let m = modelID.lowercased()
    if m.contains("fable") { return .fable }
    if m.contains("opus") { return .opus }
    if m.contains("sonnet") { return .sonnet }
    if m.contains("haiku") { return .haiku }
    return .other
}
