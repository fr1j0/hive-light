import SwiftUI
import ClaudeLightCore

/// In-place settings: the same four actions the old Settings submenu had,
/// rendered as a pane the panel flips to (no nested popovers).
struct SettingsPane: View {
    @ObservedObject var watcher: SessionWatcher
    let onBack: () -> Void

    /// Attributes-only Keychain check (no consent prompt) — gates the
    /// plan-limits toggle for API-key/Bedrock users, who have no quota.
    private let hasOAuthLogin = LimitsFetcher.oauthLoginPresent()

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
            // Extend past the 22pt content column to the 12pt panel edge, so
            // the dividers are as wide as the main view's.
            Divider().padding(.horizontal, -10)

            // Let the checkbox group breathe away from the dividers above and
            // below it, beyond the base 10pt stack spacing.
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show subagents", isOn: $watcher.showSubagents)
                Toggle("Show usage stats", isOn: $watcher.showUsageStats)
                Text("Usage row in the panel · click it for details")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
                Toggle("Show plan limits", isOn: $watcher.showPlanLimits)
                    .disabled(!hasOAuthLogin)
                Text(hasOAuthLogin
                     ? "Reads your Claude Code login from the Keychain to fetch limits from Anthropic. Nothing else is sent."
                     : "Requires a Claude subscription login in Claude Code — API-key and Bedrock/Vertex setups have no plan limits.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
                if watcher.launchAtLoginAvailable {
                    Toggle("Launch at login", isOn: Binding(
                        get: { watcher.launchAtLoginEnabled },
                        set: { _ in watcher.toggleLaunchAtLogin() }
                    ))
                }
                if watcher.notificationsAvailable {
                    Toggle("Notify when a session needs you", isOn: $watcher.notifyOnNeedsYou)
                }
            }
            .padding(.vertical, 4)

            Divider().padding(.horizontal, -10)

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
        // Match the main view's content column: cards carry their own
        // horizontal 10 on top of the 12pt frame, so its content sits at 22.
        .padding(.vertical, 12)
        .padding(.horizontal, 22)
    }
}
