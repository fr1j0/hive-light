import SwiftUI
import ClaudeLightCore

/// The panel's lamp colors — same sRGB values the menu icons used.
enum PanelPalette {
    static let red = Color(red: 1.00, green: 0.23, blue: 0.19)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.00)
    static let green = Color(red: 0.20, green: 0.78, blue: 0.35)

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
                Text(cardTitle(for: session))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let fraction = session.contextFraction {
                    ContextTicks(fraction: fraction)
                }
                Text(timerText(for: session, now: now))
                    .font(.system(size: 11, weight: needsYou(session.status) ? .semibold : .regular))
                    .foregroundStyle(needsYou(session.status)
                                     ? AnyShapeStyle(PanelPalette.red)
                                     : AnyShapeStyle(.secondary))
            }
            if let subtitle = cardSubtitle(for: session, errorReason: errorReason) {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(session.status == .error
                                     ? AnyShapeStyle(PanelPalette.red)
                                     : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        .accessibilityLabel([ClaudeLightCore.accessibilityLabel(for: session),
                             cardSubtitle(for: session, errorReason: errorReason)]
                            .compactMap { $0 }.joined(separator: ". "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { TerminalFocuser.focus(session) }
    }
}

/// The collapsible subagent block inside a card. Expanded: named mini-rows
/// (failures red) behind a guide line, plus the overflow line. Collapsed:
/// the compact chip ("⑂ 4 subagents · 1 failed").
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
                    Text(collapsed ? subagentChipText(list) : "subagents")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if !collapsed {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(list.visible, id: \.id) { sub in
                        HStack(spacing: 4) {
                            if sub.state == .failed {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(PanelPalette.red)
                            }
                            Text(sub.label)
                                .font(.system(size: 11))
                                .foregroundStyle(sub.state == .failed
                                                 ? AnyShapeStyle(PanelPalette.red)
                                                 : AnyShapeStyle(.tertiary))
                                .lineLimit(1)
                        }
                    }
                    if list.overflowRunning > 0 {
                        Text("+\(list.overflowRunning) more running")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 2)
                }
            }
        }
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
        .help(contextTooltip(fraction: fraction))
        .accessibilityLabel(contextTooltip(fraction: fraction))
    }

    private static func color(for level: ContextLevel) -> Color {
        switch level {
        case .ok: return Color.secondary
        case .warm: return PanelPalette.orange
        case .hot: return PanelPalette.red
        }
    }
}
