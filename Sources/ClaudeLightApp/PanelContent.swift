import SwiftUI
import AppKit
import ClaudeLightCore

/// The custom dropdown panel (#86): header summary, one card per session
/// (live timers via TimelineView, ticking only while the panel is open),
/// a reserved stats slot (#83), and a footer. The gear flips the whole
/// content to SettingsPane in place.
struct PanelContent: View {
    @ObservedObject var watcher: SessionWatcher
    @State private var showingSettings = false
    @State private var showingUsage = false
    @StateObject private var usage = UsageScanner()
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
        let usageRow = (watcher.showUsageStats && !usage.snapshot.windowBurn.isEmpty) ? 1 : 0
        return watcher.sessions.count + subagentRows / 3 + usageRow
    }

    var body: some View {
        Group {
            if showingSettings {
                SettingsPane(watcher: watcher) { showingSettings = false }
            } else if showingUsage {
                Text("Usage — coming in Task 6")
                    .font(.system(size: 12))
                    .padding(12)
                    .onTapGesture { showingUsage = false }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    sessionList(now: context.date)
                }
            }
        }
        .frame(width: 340)
        .onAppear { if watcher.showUsageStats { usage.refresh(force: true) } }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if watcher.showUsageStats { usage.refresh() }
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
            if watcher.showUsageStats, !usage.snapshot.windowBurn.isEmpty {
                Divider()
                UsageRow(burn: usage.snapshot.windowBurn,
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
            } else {
                ForEach(watcher.sessions, id: \.sessionID) { session in
                    SessionCard(session: session,
                                errorReason: watcher.errorReasons[session.sessionID],
                                subagents: watcher.subagentsBySession[session.sessionID],
                                now: now)
                }
            }
        }
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
                Text("Claude Light v\(version)").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Quit Claude Light")
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
