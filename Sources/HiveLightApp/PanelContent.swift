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
    /// Past this estimated weight the list scrolls at a fixed height so the
    /// footer stays reachable. Below it, a plain stack hugs the content —
    /// the .window panel sizes to ideal height, and a bare ScrollView's
    /// ideal is ~zero (it collapses; measuring back is a layout deadlock,
    /// since a zero-height ScrollView never lays out its content).
    private static let scrollThreshold = 8
    private static let scrolledListHeight: CGFloat = 480

    /// Deterministic pre-layout size estimate: one unit per session card,
    /// with expanded subagent mini-rows (~1/3 card height each) folded in so
    /// a few heavily fanned-out sessions can't outgrow the screen either.
    private var estimatedRowWeight: Int {
        let subagentRows = watcher.subagentsBySession.values.reduce(0) {
            // A large fan-out's block scrolls internally (height-bounded at ~8
            // rows), so cap its contribution to the panel-size estimate.
            $0 + min($1.visible.count, 8)
        }
        let usageRow = usageRowVisible ? 1 : 0
        // Grouped mode adds one ~14pt header per block (~1/3 card height).
        let headerRows = watcher.sessionOrder == .project
            ? (sessionBlocks(watcher.sessions).count + 2) / 3 : 0
        return watcher.sessions.count + subagentRows / 3 + usageRow + headerRows
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
                SettingsPane(watcher: watcher) { showingSettings = false }
            } else if showingUsage {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    UsageView(snapshot: usage.snapshot,
                              limits: watcher.showPlanLimits ? limitsFetcher.limits : [],
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
            if let summary = watcher.summary {
                HStack(spacing: 8) {
                    Circle().fill(headerColor).frame(width: 8, height: 8)
                    Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                Divider()
            }

            if estimatedRowWeight > Self.scrollThreshold {
                ScrollView {
                    sessionRows(now: now)
                }
                .frame(height: Self.scrolledListHeight)
            } else {
                sessionRows(now: now)
            }

            // Stats strip (#83): the usage glance docks between the list and footer.
            if usageRowVisible {
                Divider()
                let limits = watcher.showPlanLimits ? limitsFetcher.limits : []
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
                Text("No active Claude Code sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else if watcher.sessionOrder == .project {
                // Original variant B (live verdict): EVERY block gets the
                // tiny repo header and branch-led cards — one card grammar
                // everywhere; the project name always lives in the header,
                // never sometimes-in/sometimes-out of the card.
                // id = groupKey: stable when the block's earliest session
                // expires (a member-session id would reset the whole block's
                // view state on expiry — the very churn this feature kills).
                ForEach(sessionBlocks(watcher.sessions), id: \.first!.groupKey) { block in
                    VStack(alignment: .leading, spacing: 4) {
                        // The header carries the project name — the role the
                        // classic card title plays — so it wears title color.
                        Text(blockTitle(block).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(1)
                            .foregroundStyle(.primary)
                            .padding(.top, 4)
                            .padding(.leading, 4)
                        ForEach(block, id: \.sessionID) { session in
                            card(session, now: now, grouped: true)
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
                Text("Hive Light v\(version)").font(.system(size: 11)).foregroundStyle(.tertiary)
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
