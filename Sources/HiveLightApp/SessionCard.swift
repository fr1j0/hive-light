import SwiftUI
import HiveLightCore

/// The panel's lamp colors — same sRGB values the menu icons used.
enum PanelPalette {
    static let red = Color(red: 1.00, green: 0.23, blue: 0.19)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.00)
    static let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    // 70% opacity: a quiet ref label, not a status highlight.
    static let branchAmber = Color(red: 1.00, green: 0.76, blue: 0.40).opacity(0.7)

    static func color(for status: SessionStatus) -> Color {
        switch status {
        case .waiting, .attention, .handoff, .error: return red
        case .running: return orange
        case .idle: return green
        }
    }
}

/// One session in the panel: a clickable card (status dot, title, live
/// timer, subtitle with the pending question) with collapsible subagent
/// rows.
struct SessionCard: View {
    let session: Session
    let errorReason: String?
    let subagents: SubagentList?
    let now: Date
    /// Inside a 2+ repo block (grouped order): the block header owns the
    /// repo name, so the card title leads with the branch and the
    /// branch-only subtitle is suppressed. Classic render when false.
    var grouped: Bool = false

    /// Per-card, in-memory only — resets on relaunch by design.
    @State private var subagentsCollapsed = false
    @State private var hovering = false

    var body: some View {
        card
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(PanelPalette.color(for: session.status))
                    .frame(width: 9, height: 9)
                // Grouped cards speak the app's branch vocabulary — 11pt
                // amber, exactly like the classic subtitle — so a branch ref
                // looks identical grouped or not (one hierarchy, one color).
                Text(grouped ? groupedCardTitle(for: session) : cardTitle(for: session))
                    .font(.system(size: grouped ? 11 : 13, weight: grouped ? .regular : .semibold))
                    .foregroundStyle(grouped ? AnyShapeStyle(PanelPalette.branchAmber)
                                             : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer(minLength: 8)
                // Gauge and timer share a center-aligned sub-stack: the ticks
                // carry no text baseline, so the row's .firstTextBaseline
                // alignment would seat them by their bottom edge instead.
                HStack(spacing: 5) {
                    if let fraction = session.contextFraction {
                        ContextTicks(fraction: fraction)
                    }
                    // The timer gets a reserved fixed-width slot: its text
                    // width breathes as digits roll, and letting it push the
                    // gauge around slides the tooltip region out from under a
                    // hovering cursor, killing the tooltip mid-delay. Width
                    // fits "365d".
                    Text(timerText(for: session, now: now))
                        .font(.system(size: 11, weight: needsYou(session.status) ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(needsYou(session.status)
                                         ? AnyShapeStyle(PanelPalette.red)
                                         : AnyShapeStyle(.secondary))
                        .frame(width: 28, alignment: .trailing)
                }
            }
            if let subtitle = cardSubtitle(for: session, errorReason: errorReason),
               !(grouped && subtitleShowsBranch(for: session)) {
                let isBranch = subtitleShowsBranch(for: session)
                HStack(spacing: 8) {
                    Text(subtitle)
                        .font(.system(size: isBranch ? 11 : 12))
                        .foregroundStyle(session.status == .error
                                         ? AnyShapeStyle(PanelPalette.red)
                                         : isBranch
                                         ? AnyShapeStyle(PanelPalette.branchAmber)
                                         : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let model = session.model {
                        Spacer(minLength: 6)
                        // Model chip (#105): trailing edge, never compresses —
                        // the subtitle text truncates instead.
                        Text(shortModelName(model).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.09)))
                            .layoutPriority(1)
                            .help(model)
                    }
                }
                .padding(.leading, 18)
            }
            if let list = subagents, !list.isEmpty {
                SubagentRows(list: list, collapsed: $subagentsCollapsed)
                    .padding(.leading, 18)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(hovering ? 0.10 : 0.05))
        )
        // The whole card is the focus target — hover implies clickability;
        // the inner disclosure Button still wins clicks on its own area.
        .contentShape(Rectangle())
        .onTapGesture { TerminalFocuser.focus(session) }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([HiveLightCore.accessibilityLabel(for: session),
                             cardSubtitle(for: session, errorReason: errorReason),
                             session.model.map { "model \(shortModelName($0))" },
                             session.contextFraction.map { contextTooltip(fraction: $0) }]
                            .compactMap { $0 }.joined(separator: ". "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { TerminalFocuser.focus(session) }
    }
}

/// The collapsible subagent block inside a card. Expanded: named mini-rows
/// (failures red) behind a guide line, plus the overflow line. Collapsed:
/// the compact chip ("3 of 5 done · 1 failed").
struct SubagentRows: View {
    let list: SubagentList
    @Binding var collapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(subagentChipText(list))
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if !collapsed {
                // Every agent is shown. A small fan-out lays out inline; beyond
                // maxInlineRows the block would grow the card without bound, so
                // it gets a fixed height and scrolls within — the whole list
                // stays reachable whatever the batch size. The explicit height
                // is required: a bare ScrollView here collapses the panel's
                // ideal-height sizing.
                if list.visible.count > Self.maxInlineRows {
                    ScrollView { expandedRows }
                        .frame(height: Self.scrollBlockHeight)
                } else {
                    expandedRows
                }
            }
        }
    }

    @ViewBuilder private var expandedRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(list.visible, id: \.id) { sub in
                HStack(spacing: 5) {
                    switch sub.state {
                    case .failed:
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PanelPalette.red)
                            .frame(width: 10)
                    case .done:
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            // Pale green: "succeeded", paired with the red ✗ —
                            // muted so the settled record stays quiet.
                            .foregroundStyle(PanelPalette.green.opacity(0.7))
                            .frame(width: 10)
                    case .running:
                        LivePulseDot().frame(width: 10)
                    }
                    Text(sub.label)
                        .font(.system(size: 11))
                        .strikethrough(sub.state == .done)
                        .foregroundStyle(foreground(for: sub.state))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 2)
        }
    }

    /// Above this many agents the row block scrolls internally instead of
    /// growing the card. ~8 rows tall.
    private static let maxInlineRows = 8
    private static let scrollBlockHeight: CGFloat = 128

    private func foreground(for state: Subagent.State) -> AnyShapeStyle {
        switch state {
        case .failed:  return AnyShapeStyle(PanelPalette.red)
        case .done:    return AnyShapeStyle(.tertiary)   // dimmed settled tail
        case .running: return AnyShapeStyle(.secondary)  // brighter than done
        }
    }
}

/// The live-agent marker: a small orange dot with a gentle pulse. Honors
/// reduce-motion by falling back to a static dot.
private struct LivePulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(PanelPalette.orange)
            .frame(width: 6, height: 6)
            .scaleEffect(animating ? 1.0 : 0.7)
            .opacity(animating ? 1.0 : 0.5)
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                       value: animating)
            .onAppear { if !reduceMotion { animating = true } }
    }
}

/// Five-tick context gauge (#96): lit count = usage, color = urgency.
/// The exact percentage lives only in the tooltip.
struct ContextTicks: View {
    let fraction: Double

    var body: some View {
        let lit = contextSegments(fraction: fraction)
        let color = Self.color(for: contextLevel(fraction: fraction))
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < lit ? color : Color.primary.opacity(0.15))
                    .frame(width: 4, height: 7)
            }
        }
        // Pad before .help so the tooltip region is taller than the 7pt
        // ticks — a strip that thin is too easy to slide off mid-hover.
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .help(contextTooltip(fraction: fraction))
        .accessibilityLabel(contextTooltip(fraction: fraction))
    }

    private static func color(for level: ContextLevel) -> Color {
        switch level {
        // Bright, not .secondary: on the dark panel, secondary grey is
        // nearly the unlit 15% — lit calm ticks must read as lit.
        case .ok: return Color.primary.opacity(0.75)
        case .warm: return PanelPalette.orange
        case .hot: return PanelPalette.red
        }
    }
}
