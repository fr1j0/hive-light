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
/// cap), model chips beneath, reset countdown at the trailing edge. The whole
/// row is a button into the Usage view.
struct UsageRow: View {
    let burn: [ModelBurn]      // descending, from the scanner
    let windowEnd: Date?
    let now: Date
    let onOpen: () -> Void

    private static let maxChips = 3

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 5) {
                microbar
                chips
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .accessibilityLabel(accessibilityText)
    }

    private var total: Int { burn.reduce(0) { $0 + $1.tokens } }

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
        .frame(height: 5)
    }

    private var chips: some View {
        HStack(spacing: 10) {
            ForEach(burn.prefix(Self.maxChips), id: \.model) { b in
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
            if burn.count > Self.maxChips {
                Text("+\(burn.count - Self.maxChips)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let end = windowEnd {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9))
                    Text(resetText(until: end, now: now))
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var accessibilityText: String {
        let parts = burn.map { "\(UsagePalette.chipName($0.model)) \(tokenText($0.tokens))" }
        let reset = windowEnd.map { ", window resets in \(resetText(until: $0, now: now))" } ?? ""
        return "Usage: " + parts.joined(separator: ", ") + reset
    }
}
