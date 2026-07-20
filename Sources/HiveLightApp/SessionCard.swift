import SwiftUI
import AppKit
import HiveLightCore

/// The panel's lamp colors — same sRGB values the menu icons used.
enum PanelPalette {
    static let red = Color(red: 1.00, green: 0.23, blue: 0.19)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.00)
    static let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    // A quiet ref label, not a status highlight. Amber stays the git-ref
    // color in both themes, but the value adapts: the pale 70% amber that
    // glows on dark material is unreadable on light (#147), so light mode
    // gets a deep amber (~5:1 on the panel material).
    static let branchAmber = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.00, green: 0.76, blue: 0.40, alpha: 0.70)
            : NSColor(srgbRed: 0.55, green: 0.36, blue: 0.02, alpha: 0.92)
    })

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
    let taskSummary: TaskSummary?
    let now: Date
    /// Inside a 2+ repo block (grouped order): the block header owns the
    /// repo name, so the card title leads with the branch and the
    /// branch-only subtitle is suppressed. Classic render when false.
    var grouped: Bool = false

    /// Per-card, in-memory only — resets on relaunch by design.
    @State private var subagentsCollapsed = false
    @State private var taskHistoryExpanded = false
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
            let visibleSubtitle: String? = {
                guard let s = cardSubtitle(for: session, errorReason: errorReason),
                      !(grouped && subtitleShowsBranch(for: session)) else { return nil }
                // No bare status words on this line — the dot already carries
                // status. Keep only informative subtitles (questions, error
                // reasons, branches); drop plain "running"/"idle"/etc.
                if s == friendlyStatusLabel(for: session.status) { return nil }
                return s
            }()
            if let subtitle = visibleSubtitle {
                let isBranch = subtitleShowsBranch(for: session)
                Text(subtitle)
                    .font(.system(size: isBranch ? 11 : 12))
                    .foregroundStyle(session.status == .error
                                     ? AnyShapeStyle(PanelPalette.red)
                                     : isBranch
                                     ? AnyShapeStyle(PanelPalette.branchAmber)
                                     : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 18)
            }
            if let summary = taskSummary {
                TaskBlock(summary: summary, historyExpanded: $taskHistoryExpanded)
                    .padding(.leading, 18)
                    .padding(.top, 2)
            }
            if let list = subagents, !list.isEmpty {
                // With an owning-task line above, the fan-out nests one level
                // deeper — the agents belong to the task, not the session row.
                SubagentRows(list: list, collapsed: $subagentsCollapsed)
                    .padding(.leading, taskSummary == nil ? 18 : 30)
                    .padding(.top, 3)
            }
        }
        // Reserve room for the chip overlay's fixed slot so a single-line card
        // (no tasks/subagents) is sized to hold it, rather than the chip
        // reading as a tacked-on second line.
        .frame(minHeight: 34, alignment: .top)
        // Model chip (#105): pinned top-right, directly under the gauge/timer,
        // as an OVERLAY — it takes no row in the layout, so tasks and subagents
        // stack as if it weren't there. It never moves down with content and
        // never leaves an empty row. Position is sacred.
        //
        // ⚠️ LOCKED 2026-07-20 by explicit user decision after a long, painful
        // iteration. DO NOT move the chip into the flow, onto the task/subtitle
        // row, or anywhere else. The overlay IS the design. Leave it alone.
        .overlay(alignment: .topTrailing) {
            if let model = session.model {
                ModelChip(model: model)
                    .padding(.top, 19)
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
                             taskSummary.map { "task \(taskLineText($0))" },
                             session.model.map { "model \(shortModelName($0))" },
                             session.contextFraction.map { contextTooltip(fraction: $0) }]
                            .compactMap { $0 }.joined(separator: ". "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { TerminalFocuser.focus(session) }
    }
}

/// The model chip (#105): 9pt pill at a row's trailing edge, never
/// compresses — whatever shares the row truncates instead.
struct ModelChip: View {
    let model: String

    var body: some View {
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

/// The owning-task block: an optional count-free "earlier tasks" disclosure
/// that hides the full completed history (struck rows, chronological, long
/// histories scroll internally), then the current task at full text strength
/// behind the terminal's ■ marker.
struct TaskBlock: View {
    let summary: TaskSummary
    @Binding var historyExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let toggle = taskHistoryToggleText(summary) {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { historyExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: historyExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(toggle)
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)

                if historyExpanded {
                    // Chronological unfold of the full history. Long
                    // histories scroll internally, same cap as the fan-out
                    // block.
                    if summary.doneSubjects.count > Self.maxInlineRows {
                        ScrollView { historyRows(summary.doneSubjects) }
                            .frame(height: Self.scrollBlockHeight)
                    } else {
                        historyRows(summary.doneSubjects)
                    }
                }
            }
            HStack(spacing: 5) {
                Rectangle()
                    .fill(PanelPalette.color(for: .running))
                    .frame(width: 7, height: 7)
                    .cornerRadius(1.5)
                (Text(summary.inProgressSubject)
                    .foregroundColor(.primary)
                 + Text(" · \(summary.doneCount)/\(summary.total) tasks")
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor)))
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // Progress echo of the "· done/total" count — shape channel only,
            // no number (the text already says it once).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(PanelPalette.orange.opacity(0.75))
                        .frame(width: geo.size.width * taskProgressFraction(summary))
                }
            }
            // Greedy width: a GeometryReader's ideal width is ~10pt and this
            // panel sizes to ideals — without maxWidth the bar collapses.
            .frame(maxWidth: .infinity)
            .frame(height: 2)
            .padding(.leading, 12)
        }
    }

    @ViewBuilder private func historyRows(_ subjects: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(subjects.enumerated()), id: \.offset) { _, subject in
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PanelPalette.green.opacity(0.7))
                        .frame(width: 10)
                    Text(subject)
                        .font(.system(size: 11))
                        .strikethrough()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private static let maxInlineRows = 8
    private static let scrollBlockHeight: CGFloat = 128
}

/// The collapsible subagent block inside a card. Expanded: named mini-rows
/// (failures red) behind a guide line, plus the overflow line. Collapsed:
/// the compact chip ("3 of 5 done · 1 failed").
struct SubagentRows: View {
    let list: SubagentList
    @Binding var collapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
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
            }

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
