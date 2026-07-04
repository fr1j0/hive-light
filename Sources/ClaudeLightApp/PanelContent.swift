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

    var body: some View {
        Group {
            if showingSettings {
                SettingsPane(watcher: watcher) { showingSettings = false }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    sessionList(now: context.date)
                }
            }
        }
        .frame(width: 340)
    }

    @ViewBuilder
    private func sessionList(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let summary = watcher.summary {
                HStack(spacing: 8) {
                    Circle().fill(headerColor).frame(width: 8, height: 8)
                    Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                Divider()
            }

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

            // Stats strip (#83) docks between this divider and the footer.
            Divider()
            footer
        }
        .padding(8)
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
                Text("v\(version)").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Quit Claude Light")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
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
