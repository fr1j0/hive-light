import SwiftUI
import ClaudeLightCore

/// The dedicated usage pane (#83): current-window per-model bars + reset,
/// then daily history (Claude Code's stats cache + a live `today` row).
/// Same flip mechanism and rhythm as SettingsPane.
struct UsageView: View {
    let snapshot: UsageSnapshot
    let limits: [PlanLimit]
    let now: Date
    let onBack: () -> Void

    /// Stacked segments keep FIXED model order so days compare visually
    /// (the live row sorts by burn instead — a composition reads best
    /// biggest-first, a stack needs stable order).
    private static let stackOrder: [ModelColorSlot] = [.fable, .opus, .sonnet, .haiku, .other]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().padding(.horizontal, -10)

            if snapshot.windowBurn.isEmpty && days.isEmpty && limits.isEmpty {
                Text("No usage recorded yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                if !limits.isEmpty {
                    planLimitsSection
                    Divider().padding(.horizontal, -10)
                }
                currentWindow
                Divider().padding(.horizontal, -10)
                daily
                Divider().padding(.horizontal, -10)
                footnote
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 22)
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("Back").font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            Text("Usage").font(.system(size: 12, weight: .semibold))
            Spacer()
            // Mirror the back control's width so the title stays centered.
            HStack(spacing: 3) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                Text("Back").font(.system(size: 12))
            }.hidden()
        }
    }

    // MARK: - Plan limits (fetched — real percentages)

    @ViewBuilder private var planLimitsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionTitle("Plan limits")
            ForEach(limits, id: \.label) { limit in
                HStack(spacing: 8) {
                    Text(limit.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.08))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Self.levelColor(limitLevel(limit)))
                                .frame(width: geo.size.width * CGFloat(min(limit.percent, 100)) / 100)
                        }
                    }
                    .frame(height: 8)
                    Text("\(limit.percent)%")
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    HStack(spacing: 3) {
                        if let reset = limitResetText(kind: limit.kind, resetsAt: limit.resetsAt, now: now) {
                            Image(systemName: "timer").font(.system(size: 8))
                            Text(reset).font(.system(size: 10)).monospacedDigit()
                        }
                    }
                    .foregroundStyle(.tertiary)
                    .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }

    /// Capacity bars speak the context gauge's urgency language — never the
    /// model categorical palette (capacity, not identity).
    private static func levelColor(_ level: ContextLevel) -> Color {
        switch level {
        case .ok: return Color.primary.opacity(0.75)
        case .warm: return PanelPalette.orange
        case .hot: return PanelPalette.red
        }
    }

    // MARK: - Current window

    @ViewBuilder private var currentWindow: some View {
        if !snapshot.windowBurn.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                sectionTitle("Current window")
                let maxTokens = snapshot.windowBurn.first?.tokens ?? 1
                ForEach(snapshot.windowBurn, id: \.model) { b in
                    HStack(spacing: 8) {
                        modelLabel(b.model).frame(width: 66, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.08))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(UsagePalette.color(forModel: b.model))
                                    .frame(width: geo.size.width * CGFloat(b.tokens) / CGFloat(max(maxTokens, 1)))
                            }
                        }
                        .frame(height: 8)
                        Text(tokenText(b.tokens))
                            .font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                if let end = snapshot.windowEnd {
                    HStack(spacing: 6) {
                        Image(systemName: "timer").font(.system(size: 9))
                        Text("window resets in ").font(.system(size: 11))
                        + Text(resetText(until: end, now: now))
                            .font(.system(size: 11, weight: .semibold))
                        + Text(" · \(Self.wallClock.string(from: end))")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                }
            }
        }
    }

    // MARK: - Daily history

    private struct Day: Identifiable {
        let id: String            // date key or "today"
        let label: String
        let tokensByModel: [String: Int]
        let isToday: Bool
        var total: Int { tokensByModel.values.reduce(0, +) }
    }

    /// Last 4 cache days before today + a live `today` row. The live number
    /// wins over any cache entry for today — the cache lags a day.
    private var days: [Day] {
        let todayKey = Self.dayKey.string(from: now)
        var rows: [Day] = snapshot.dailyHistory
            .filter { $0.date < todayKey }
            .sorted { $0.date < $1.date }
            .suffix(4)
            .map { Day(id: $0.date, label: Self.dayLabel($0.date),
                       tokensByModel: $0.tokensByModel, isToday: false) }
        if !snapshot.todayBurn.isEmpty {
            let tokens = Dictionary(uniqueKeysWithValues: snapshot.todayBurn.map { ($0.model, $0.tokens) })
            rows.append(Day(id: "today", label: "today", tokensByModel: tokens, isToday: true))
        }
        return rows
    }

    @ViewBuilder private var daily: some View {
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                sectionTitle("Daily · last \(days.count) days")
                let maxTotal = days.map(\.total).max() ?? 1
                ForEach(days) { day in
                    HStack(spacing: 8) {
                        Text(day.label)
                            .font(.system(size: 10, weight: day.isToday ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(day.isToday ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                            .frame(width: 44, alignment: .leading)
                        GeometryReader { geo in
                            let segments = slotTotals(day.tokensByModel)
                            let scale = CGFloat(day.total) / CGFloat(max(maxTotal, 1))
                            let gaps = CGFloat(max(segments.count - 1, 0)) * 2
                            let available = max(geo.size.width * scale - gaps, 0)
                            HStack(spacing: 2) {
                                ForEach(segments, id: \.slot.hashValue) { seg in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(UsagePalette.color(for: seg.slot))
                                        .frame(width: max(3, available * CGFloat(seg.tokens) / CGFloat(max(day.total, 1))))
                                }
                            }
                        }
                        .frame(height: 8)
                        .clipped()
                        .help(hoverText(day))
                        Text(tokenText(day.total))
                            .font(.system(size: 10)).monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                legend
            }
        }
    }

    private func slotTotals(_ tokens: [String: Int]) -> [(slot: ModelColorSlot, tokens: Int)] {
        var sums: [ModelColorSlot: Int] = [:]
        for (model, t) in tokens { sums[modelColorSlot(model), default: 0] += t }
        return Self.stackOrder.compactMap { slot in sums[slot].map { (slot, $0) } }
    }

    private func hoverText(_ day: Day) -> String {
        slotTotals(day.tokensByModel)
            .map { "\(slotName($0.slot)) \(tokenText($0.tokens))" }
            .joined(separator: " · ")
    }

    private var legend: some View {
        let slots = Self.stackOrder.filter { slot in
            days.contains { day in day.tokensByModel.contains { modelColorSlot($0.key) == slot } }
        }
        return HStack(spacing: 12) {
            ForEach(slots, id: \.hashValue) { slot in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(UsagePalette.color(for: slot))
                        .frame(width: 6, height: 6)
                    Text(slotName(slot))
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func slotName(_ slot: ModelColorSlot) -> String {
        switch slot {
        case .fable: return "FABLE"
        case .opus: return "OPUS"
        case .sonnet: return "SONNET"
        case .haiku: return "HAIKU"
        case .other: return "OTHER"
        }
    }

    private var footnote: some View {
        Text("Plan limits come from Anthropic with your Claude Code login (opt-in). Everything else is local — window from your transcripts, history from Claude Code's stats cache; those bars compare models to each other, never to a limit.")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            // Wrap, don't truncate: the .window panel sizes to ideal height,
            // which single-lines an unconstrained Text into an ellipsis.
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .kerning(1)
            .foregroundStyle(.tertiary)
    }

    private func modelLabel(_ id: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(UsagePalette.color(forModel: id))
                .frame(width: 6, height: 6)
            Text(UsagePalette.chipName(id))
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Date helpers

    private static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()
    private static let dayOut: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()
    private static let wallClock: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()
    private static func dayLabel(_ key: String) -> String {
        dayKey.date(from: key).map { dayOut.string(from: $0) } ?? key
    }
}
