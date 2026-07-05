import SwiftUI
import ClaudeLightCore

/// In-place settings: the same four actions the old Settings submenu had,
/// rendered as a pane the panel flips to (no nested popovers).
struct SettingsPane: View {
    @ObservedObject var watcher: SessionWatcher
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                Text("Settings").font(.system(size: 12, weight: .semibold))
                Spacer()
                // Mirror the back control's width so the title stays centered.
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("Back").font(.system(size: 12))
                }.hidden()
            }

            Toggle("Show subagents", isOn: $watcher.showSubagents)
            if watcher.launchAtLoginAvailable {
                Toggle("Launch at login", isOn: Binding(
                    get: { watcher.launchAtLoginEnabled },
                    set: { _ in watcher.toggleLaunchAtLogin() }
                ))
            }
            if watcher.notificationsAvailable {
                Toggle("Notify when a session needs you", isOn: $watcher.notifyOnNeedsYou)
            }

            Divider()

            Button {
                if watcher.hooksInstalled { watcher.removeHooks() } else { watcher.installHooks() }
            } label: {
                Label(watcher.hooksInstalled ? "Remove Claude Code hooks" : "Install Claude Code hooks",
                      systemImage: "link")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            if let hookError = watcher.hookActionError {
                Label {
                    Text(hookError).font(.system(size: 11))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                }
                .foregroundStyle(PanelPalette.red)
            }
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(12)
    }
}
