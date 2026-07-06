import SwiftUI
import ClaudeLightCore

/// Model colors — categorical palette validated for colorblind separation and
/// ≥3:1 contrast on the dark panel (2026-07-06 usage-stats spec). Fixed per
/// family, never cycled. Red/orange/green are reserved for session status.
enum UsagePalette {
    static func color(for slot: ModelColorSlot) -> Color {
        switch slot {
        case .fable:  return Color(red: 0.224, green: 0.529, blue: 0.898) // #3987e5
        case .opus:   return Color(red: 0.098, green: 0.620, blue: 0.439) // #199e70
        case .sonnet: return Color(red: 0.788, green: 0.522, blue: 0.000) // #c98500
        case .haiku:  return Color(red: 0.565, green: 0.522, blue: 0.914) // #9085e9
        case .other:  return Color.primary.opacity(0.35)
        }
    }
    static func color(forModel id: String) -> Color { color(for: modelColorSlot(id)) }

    /// Capacity bars speak the context gauge's urgency language — never the
    /// model palette (capacity, not identity).
    static func urgency(_ level: ContextLevel) -> Color {
        switch level {
        case .ok: return Color.primary.opacity(0.75)
        case .warm: return PanelPalette.orange
        case .hot: return PanelPalette.red
        }
    }

    /// Chip label: family name for known models, short id for others.
    static func chipName(_ id: String) -> String {
        switch modelColorSlot(id) {
        case .fable: return "FABLE"
        case .opus: return "OPUS"
        case .sonnet: return "SONNET"
        case .haiku: return "HAIKU"
        case .other: return shortModelName(id).uppercased()
        }
    }
}

/// The usage glance (#83, mockup variant B): a thin composition micro-bar of
/// the current 5h window's burn (segments relative to each other — never to a
/// cap) with the reset countdown beside it, model chips beneath. The whole
/// row is a button into the Usage view — a trailing chevron and hover
/// highlight carry the affordance. Chips never truncate: ViewThatFits drops
/// to fewer chips (+N absorbs the rest) instead of ellipsizing names/values.
struct UsageRow: View {
    let burn: [ModelBurn]      // descending, from the scanner
    /// The REAL fetched limits (opt-in). When present, the row is a compact
    /// mirror of every bucket — live testing judged composition share
    /// "cosmetic"; per-bucket capacity (especially Fable's tighter weekly
    /// tank with its own reset) is the rationing signal.
    let limits: [PlanLimit]
    let windowEnd: Date?
    let now: Date
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    if limits.isEmpty {
                        topLine
                        if !burn.isEmpty { chipsFitted }
                    } else {
                        ForEach(limits, id: \.label) { limitLine($0) }
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color.primary.opacity(hovering ? 0.08 : 0)))
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityText)
    }

    private var total: Int { burn.reduce(0) { $0 + $1.tokens } }

    /// Local-only fallback line: composition micro-bar + reset countdown
    /// (capacity isn't knowable without the fetch).
    private var topLine: some View {
        HStack(spacing: 8) {
            if burn.isEmpty {
                Text("USAGE")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
            } else {
                microbar
            }
            if let end = windowEnd {
                HStack(spacing: 3) {
                    Image(systemName: "timer").font(.system(size: 9))
                    Text(resetText(until: end, now: now))
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .foregroundStyle(.tertiary)
                .fixedSize()
                .help("Current 5h usage window — all models share it.")
            }
        }
    }

    private var microbar: some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(burn.count - 1, 0)) * 2
            let available = max(geo.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(burn, id: \.model) { b in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(UsagePalette.color(forModel: b.model))
                        .frame(width: max(3, available * CGFloat(b.tokens) / CGFloat(max(total, 1))))
                }
            }
        }
        // Greedy width: a GeometryReader's IDEAL width is ~10pt, and this row
        // sits in a layout that can consult ideals (the .window panel sizes to
        // ideal) — without maxWidth the bar collapses to a stub.
        .frame(maxWidth: .infinity)
        .frame(height: 5)
        .clipped()
        .help("How this 5h window's token burn splits across models — share, not capacity.")
    }

    /// One real limit bucket: label · usage bar · % · its own reset clock.
    private func limitLine(_ limit: PlanLimit) -> some View {
        HStack(spacing: 8) {
            Text(Self.compactLabel(limit.label))
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(UsagePalette.urgency(limitLevel(limit)))
                        .frame(width: geo.size.width * CGFloat(min(limit.percent, 100)) / 100)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 5)
            Text("\(limit.percent)%")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            HStack(spacing: 3) {
                Image(systemName: "timer").font(.system(size: 8))
                Text(limitResetText(kind: limit.kind, resetsAt: limit.resetsAt, now: now) ?? "")
                    .font(.system(size: 10))
                    .monospacedDigit()
            }
            .foregroundStyle(.tertiary)
            .frame(width: 58, alignment: .trailing)
        }
        .help(Self.limitHelp(limit))
    }

    /// The row's label column. "Session" is Anthropic's name for the rolling
    /// 5h window — but THIS panel is full of Claude Code sessions, so the word
    /// collides; "5-HOUR" says what it is. Weekly buckets spell out WEEK.
    static func compactLabel(_ label: String) -> String {
        label == "Session" ? "5-HOUR"
            : label.replacingOccurrences(of: "Week · ", with: "").uppercased()
    }

    /// Per-bucket tooltip: what the bar measures and when it resets.
    static func limitHelp(_ limit: PlanLimit) -> String {
        switch limit.kind {
        case "session":
            return "Rolling 5-hour usage window, shared by all models — real usage from Anthropic."
        case "weekly_all":
            return "Weekly budget across all models — real usage from Anthropic."
        case "weekly_scoped":
            return "\(limit.label.replacingOccurrences(of: "Week · ", with: ""))'s own tighter weekly budget — real usage from Anthropic."
        default:
            return "\(limit.label) — real usage toward your plan limit, from Anthropic."
        }
    }

    /// Widest chip line that fits without truncation; the +N count absorbs
    /// whatever gets dropped.
    private var chipsFitted: some View {
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                chipsLine(showing: 3)
                chipsLine(showing: 2)
                chipsLine(showing: 1)
            }
            Spacer(minLength: 0)
        }
    }

    private func chipsLine(showing count: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(burn.prefix(count), id: \.model) { b in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(UsagePalette.color(forModel: b.model))
                        .frame(width: 6, height: 6)
                    Text(UsagePalette.chipName(b.model))
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(.secondary)
                    Text(tokenText(b.tokens))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if burn.count > count {
                Text("+\(burn.count - count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .fixedSize()
    }

    private var accessibilityText: String {
        if !limits.isEmpty {
            let parts = limits.map { limit in
                "\(limit.label) \(limit.percent) percent"
                    + (limitResetText(kind: limit.kind, resetsAt: limit.resetsAt, now: now)
                        .map { ", resets \($0)" } ?? "")
            }
            return "Plan limits: " + parts.joined(separator: "; ")
        }
        let parts = burn.map { "\(UsagePalette.chipName($0.model)) \(tokenText($0.tokens))" }
        let reset = windowEnd.map { ", window resets in \(resetText(until: $0, now: now))" } ?? ""
        return "Usage: " + parts.joined(separator: ", ") + reset
    }
}
