import SwiftUI
import AppKit
import HiveLightCore

/// The custom dropdown panel (#86): header summary, one card per session
/// (live timers via TimelineView, ticking only while the panel is open),
/// a reserved stats slot (#83), and a footer. The gear flips the whole
/// content to SettingsPane in place.
struct PanelContent: View {
    @ObservedObject var watcher: SessionWatcher
    @State private var showingSettings = false
    @State private var showingUsage = false
    @StateObject private var usage = UsageScanner()
    @StateObject private var limitsFetcher = LimitsFetcher()
    // Past the panelScrollThreshold weight the list scrolls at a height that
    // tracks the estimate (panelListScrollHeight). Below it, a plain stack
    // hugs the content — the .window panel sizes to ideal height, and a bare
    // ScrollView's ideal is ~zero (it collapses; measuring back is a layout
    // deadlock, since a zero-height ScrollView never lays out its content).

    /// Deterministic pre-layout size estimate: one unit per session card,
    /// with expanded subagent mini-rows (~1/3 card height each) folded in so
    /// a few heavily fanned-out sessions can't outgrow the screen either.
    private var estimatedRowWeight: Int {
        // Iterate the same blocks the list renders so a FOLDED group counts as
        // just its header (its cards aren't drawn) — otherwise the scroll frame
        // over-reserves and reopens the bottom gap.
        let grouped = watcher.sessionOrder == .project
        let blocks = grouped ? sessionBlocks(watcher.sessions) : [watcher.sessions]
        var sessionCount = 0, subCells = 0, taskCells = 0, headerCells = 0
        for block in blocks {
            if grouped { headerCells += 1 }
            if grouped, let key = block.first?.groupKey, watcher.collapsedGroups.contains(key) {
                continue   // folded: header only, cards hidden
            }
            sessionCount += block.count
            for s in block {
                if let sub = watcher.subagentsBySession[s.sessionID] {
                    subCells += min(sub.visible.count, 8)   // fan-out scrolls internally past ~8
                }
                if let t = watcher.taskSummaryBySession[s.sessionID] {
                    taskCells += 1 + (taskHistoryToggleText(t) == nil ? 0 : 1)
                }
            }
        }
        let usageRow = usageRowVisible ? 1 : 0
        // Sub/task mini-rows and group headers each weigh ~1/3 of a card.
        return sessionCount + (subCells + taskCells + headerCells) / 3 + usageRow
    }

    /// Most-urgent status color across a group's sessions — the folded
    /// header's dot, so a collapsed group still signals what it's doing.
    private func groupStatusColor(_ block: [Session]) -> Color {
        for status: SessionStatus in [.error, .waiting, .attention, .handoff, .running, .idle]
        where block.contains(where: { $0.status == status }) {
            return PanelPalette.color(for: status)
        }
        return .secondary
    }

    /// The freshest activity age in a group — the folded header's timer.
    private func groupNewestTimer(_ block: [Session], now: Date) -> String {
        guard let newest = block.max(by: { $0.updatedAt < $1.updatedAt }) else { return "" }
        return timerText(for: newest, now: now)
    }

    /// The usage row is the door to the Usage view — visible when its toggle
    /// is on and EITHER local burn or fetched limits have something to show.
    private var usageRowVisible: Bool {
        watcher.showUsageStats
            && (!usage.snapshot.windowBurn.isEmpty
                || (watcher.showPlanLimits && !limitsFetcher.limits.isEmpty))
    }

    var body: some View {
        Group {
            if showingSettings {
                SettingsPane(watcher: watcher,
                             perModelBuckets: limitsFetcher.limits.filter(isPerModelLimit)) {
                    showingSettings = false
                }
            } else if showingUsage {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    UsageView(snapshot: usage.snapshot,
                              limits: watcher.showPlanLimits
                                ? visibleLimits(limitsFetcher.limits, overrides: watcher.usageModelOverrides)
                                : [],
                              now: context.date) { showingUsage = false }
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    sessionList(now: context.date)
                }
            }
        }
        .frame(width: 340)
        .task {
            // View-identity lifetime: starts when the panel opens, cancels on
            // close; immune to body re-evaluation (an inline Timer.publish here
            // would be recreated by every animationPhase tick and never fire).
            if watcher.showUsageStats { usage.refresh(force: true) }
            if watcher.showPlanLimits { limitsFetcher.refresh(force: true) }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if watcher.showUsageStats { usage.refresh() }
                if watcher.showPlanLimits { limitsFetcher.refresh() }   // fetcher self-throttles to 5 min
            }
        }
        .onChange(of: watcher.showUsageStats) { enabled in
            if enabled { usage.refresh(force: true) }
        }
        .onChange(of: watcher.showPlanLimits) { enabled in
            if enabled { limitsFetcher.refresh(force: true) }
        }
    }

    @ViewBuilder
    private func sessionList(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let voice = headerVoice(for: statusCounts(for: watcher.sessions))
            HStack(spacing: 10) {
                if watcher.sessions.isEmpty {
                    // Asleep: hollow ring, no halo — same grammar as the
                    // menu-bar icon's punched placeholder.
                    Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.6)
                        .frame(width: 11, height: 11)
                } else {
                    // The halo buzzes on the icon's breathe curve while the
                    // hive is humming — same clock, same rhythm as the
                    // menu-bar lamp; steady for every other state.
                    let buzzing = watcher.icon.orange == .breathe && watcher.icon.red == .off
                    let breath = buzzing ? litAlpha(for: .breathe, phase: watcher.animationPhase) : 1.0
                    Circle().fill(headerColor)
                        .frame(width: 11, height: 11)
                        .shadow(color: headerColor.opacity(0.9 * breath),
                                radius: 2 + 3 * breath)
                        .shadow(color: headerColor.opacity(0.5 * breath),
                                radius: 5 + 6 * breath)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(voice.title).font(.system(size: 13, weight: .semibold))
                    Text(voice.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            Divider()

            if let height = panelListScrollHeight(forRowWeight: estimatedRowWeight) {
                ScrollView {
                    sessionRows(now: now)
                }
                .frame(height: height)
            } else {
                sessionRows(now: now)
            }

            // Stats strip (#83): the usage glance docks between the list and footer.
            if usageRowVisible {
                Divider()
                let limits = watcher.showPlanLimits
                    ? visibleLimits(limitsFetcher.limits, overrides: watcher.usageModelOverrides)
                    : []
                UsageRow(burn: usage.snapshot.windowBurn,
                         limits: limits,
                         windowEnd: usage.snapshot.windowEnd,
                         now: now) { showingUsage = true }
            }
            Divider()
            footer
        }
        .padding(12)
    }

    @ViewBuilder
    private func sessionRows(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if watcher.sessions.isEmpty {
                // The asleep header carries the empty-state message.
                EmptyView()
            } else if watcher.sessionOrder == .project {
                // Original variant B (live verdict): EVERY block gets the
                // tiny repo header and branch-led cards — one card grammar
                // everywhere; the project name always lives in the header,
                // never sometimes-in/sometimes-out of the card.
                // id = groupKey: stable when the block's earliest session
                // expires (a member-session id would reset the whole block's
                // view state on expiry — the very churn this feature kills).
                ForEach(sessionBlocks(watcher.sessions), id: \.first!.groupKey) { block in
                    let key = block.first!.groupKey
                    let collapsed = watcher.collapsedGroups.contains(key)
                    VStack(alignment: .leading, spacing: 4) {
                        // The header carries the project name (title color) and
                        // is the fold control — a chevron toggles the group.
                        // Folded, it keeps a status dot + freshest timer so the
                        // project still reads as alive.
                        Button {
                            // No animation: the panel window re-measures its
                            // ideal height on this change, and animating a whole
                            // group in/out races that re-measure — transitioning
                            // cards overlap their neighbors. Instant fold keeps
                            // the layout consistent every frame.
                            if collapsed { watcher.collapsedGroups.remove(key) }
                            else { watcher.collapsedGroups.insert(key) }
                        } label: {
                            HStack(spacing: 6) {
                                // Project name leads at full prominence — the
                                // fold chevron trails, quiet, so it never
                                // competes with the header it controls.
                                Text(blockTitle(block).uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .kerning(1)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if collapsed {
                                    Circle().fill(groupStatusColor(block))
                                        .frame(width: 7, height: 7)
                                    Text(groupNewestTimer(block, now: now))
                                        .font(.system(size: 10))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 4)
                            .padding(.leading, 4)
                            .padding(.trailing, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if !collapsed {
                            ForEach(block, id: \.sessionID) { session in
                                card(session, now: now, grouped: true)
                            }
                        }
                    }
                }
            } else {
                ForEach(watcher.sessions, id: \.sessionID) { session in
                    card(session, now: now, grouped: false)
                }
            }
        }
    }

    private func card(_ session: Session, now: Date, grouped: Bool) -> some View {
        SessionCard(session: session,
                    errorReason: watcher.errorReasons[session.sessionID],
                    subagents: watcher.subagentsBySession[session.sessionID],
                    taskSummary: watcher.taskSummaryBySession[session.sessionID],
                    now: now,
                    grouped: grouped)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { showingSettings = true } label: {
                Label("Settings", systemImage: "gearshape").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            // A failed hook install stays visible without opening Settings.
            if let hookError = watcher.hookActionError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(PanelPalette.red)
                    .help(hookError)
                    .accessibilityLabel(hookError)
            }

            Spacer()

            if let version = Self.appVersion {
                // The panel's one brand touch (see 2026-07-06 spec): a hollow hive
                // cell folded into the wordmark — same tertiary as the text, so it
                // reads as part of the name, never as a status signal.
                HStack(spacing: 5) {
                    Image(systemName: "hexagon")
                        .font(.system(size: 9))
                        .accessibilityHidden(true)
                    Text("Hive Light v\(version)").font(.system(size: 11))
                }
                .foregroundStyle(.tertiary)
            }
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Quit Hive Light")
        }
        // The gearshape SF Symbol carries leading whitespace in its glyph box;
        // pull the leading in 2pt so it optically aligns with the header dot.
        .padding(.leading, 8)
        .padding(.trailing, 10)
    }

    private var headerColor: Color {
        if watcher.icon.red != .off { return PanelPalette.red }
        if watcher.icon.orange != .off { return PanelPalette.orange }
        if watcher.icon.green != .off { return PanelPalette.green }
        return Color.secondary
    }

    /// The running app's marketing version (CFBundleShortVersionString).
    private static let appVersion: String? =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
}
