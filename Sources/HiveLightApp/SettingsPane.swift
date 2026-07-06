import SwiftUI
import HiveLightCore

/// In-place settings: the panel flips to this pane (no nested popovers).
/// Variant B redesign: three titled card groups (SESSIONS / USAGE /
/// GENERAL) plus a hooks-action card, in the session-card surface language
/// (5% primary fill, 8pt radius) with monochrome panel-native controls.
struct SettingsPane: View {
    @ObservedObject var watcher: SessionWatcher
    let onBack: () -> Void

    /// Attributes-only Keychain check (no consent prompt) — gates the
    /// plan-limits toggle for API-key/Bedrock users, who have no quota.
    private let hasOAuthLogin = LimitsFetcher.oauthLoginPresent()

    @State private var hookHover = false

    // Layout invariants: outer padding is 12 to match PanelContent, so the
    // full-width divider aligns with the main view's. Cards span the
    // 12-inset column; card content pads 10 more, landing text at 22 — the
    // same content column the old pane used. Section titles indent 10 to
    // sit on the card content edge.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            Divider()

            sectionTitle("Sessions")
            card {
                row("Sort sessions") {
                    SegmentedPicker(selection: $watcher.sessionOrder,
                                    options: [("By project", SessionOrder.project),
                                              ("Opened", SessionOrder.opened)])
                }
                insetDivider
                row("Show subagents") {
                    MiniSwitch(isOn: $watcher.showSubagents, label: "Show subagents")
                }
            }

            sectionTitle("Usage")
            card {
                row("Show usage stats") {
                    MiniSwitch(isOn: $watcher.showUsageStats, label: "Show usage stats")
                }
                caption("Usage row in the panel · click it for details")
                insetDivider
                row("Show plan limits") {
                    MiniSwitch(isOn: $watcher.showPlanLimits, label: "Show plan limits")
                        .disabled(!hasOAuthLogin)
                }
                .opacity(hasOAuthLogin ? 1 : 0.4)
                caption(hasOAuthLogin
                        ? "Reads your Claude Code login from the Keychain to fetch limits from Anthropic. Nothing else is sent."
                        : "Requires a Claude subscription login in Claude Code — API-key and Bedrock/Vertex setups have no plan limits.")
            }

            if watcher.launchAtLoginAvailable || watcher.notificationsAvailable {
                sectionTitle("General")
                card {
                    if watcher.launchAtLoginAvailable {
                        row("Launch at login") {
                            MiniSwitch(isOn: Binding(
                                get: { watcher.launchAtLoginEnabled },
                                set: { _ in watcher.toggleLaunchAtLogin() }
                            ), label: "Launch at login")
                        }
                    }
                    if watcher.launchAtLoginAvailable && watcher.notificationsAvailable {
                        insetDivider
                    }
                    if watcher.notificationsAvailable {
                        row("Notify when a session needs you") {
                            MiniSwitch(isOn: $watcher.notifyOnNeedsYou,
                                       label: "Notify when a session needs you")
                        }
                    }
                }
            }

            hooksCard
                .padding(.top, 14)

            if let hookError = watcher.hookActionError {
                Label {
                    Text(hookError).font(.system(size: 11))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                }
                .foregroundStyle(PanelPalette.red)
                .padding(.top, 8)
                .padding(.horizontal, 10)
            }
        }
        .padding(12)
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
            Text("Settings").font(.system(size: 12, weight: .semibold))
            Spacer()
            // Mirror the back control's width so the title stays centered.
            HStack(spacing: 3) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                Text("Back").font(.system(size: 12))
            }.hidden()
        }
    }

    /// The panel's section-title treatment (Usage view, grouped list).
    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .kerning(1)
            .foregroundStyle(.tertiary)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .padding(.leading, 10)
    }

    /// Session-card surface: 5% primary fill, 8pt radius.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    /// Label leading, control trailing.
    private func row<Control: View>(_ label: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12))
            Spacer(minLength: 0)
            control()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    /// Under-label hint; trailing inset keeps it out of the control column.
    private func caption(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, -3)
            .padding(.leading, 10)
            .padding(.trailing, 56)
            .padding(.bottom, 7)
    }

    /// Hairline between rows, inset to the card's content edge.
    private var insetDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 10)
    }

    /// The one clickable card — it alone gets the 10% hover fill.
    private var hooksCard: some View {
        Button {
            if watcher.hooksInstalled { watcher.removeHooks() } else { watcher.installHooks() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "link").font(.system(size: 11))
                Text(watcher.hooksInstalled ? "Remove Claude Code hooks" : "Install Claude Code hooks")
                    .font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(hookHover ? 0.10 : 0.05)))
        .onHover { hookHover = $0 }
    }
}
