# Settings Pane Redesign (Variant B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the settings pane as approved mockup variant B — titled card groups in the session-card surface language with custom monochrome controls — with zero behavior changes.

**Architecture:** Two new reusable panel-native controls (`MiniSwitch`, `SegmentedPicker`) in a new `PanelControls.swift`, then a rebuilt `SettingsPane.swift` body composed from small private builders (sectionTitle / card / row / caption / insetDivider). All state stays in the existing `SessionWatcher` `@Published` bindings.

**Tech Stack:** SwiftUI (macOS), Swift Package Manager. Spec: `docs/superpowers/specs/2026-07-06-settings-pane-redesign-design.md`. Mockup: https://claude.ai/code/artifact/d9c90d4b-ed2d-4367-b6ef-90d39d88c38f

## Global Constraints

- No stock control styles (`.checkbox`, `.switch`, `.radioGroup`, `.segmented`) — they tint system blue; controls are monochrome `Color.primary` opacities only.
- Only sanctioned colors: `Color.primary`/`.secondary`/`.tertiary` opacities for structure, `PanelPalette.red` for the hook error. No new hues.
- `SessionWatcher` bindings and behavior untouched: same seven settings, same `hasOAuthLogin` gating, same `launchAtLoginAvailable`/`notificationsAvailable` conditionals, same flip-in-place navigation.
- Panel width is 340pt (set by `PanelContent`); nothing may force it wider.
- All existing tests must stay green: `swift test` → 333 passing.
- Views in `ClaudeLightApp` have no unit-test target — verification is `swift build` + full `swift test` regression + the live-tune loop (repo convention).
- Commit messages: conventional prefix, no AI attribution of any kind.

---

### Task 1: Panel-native monochrome controls

**Files:**
- Create: `Sources/ClaudeLightApp/PanelControls.swift`

**Interfaces:**
- Consumes: nothing project-specific (pure SwiftUI).
- Produces: `MiniSwitch(isOn: Binding<Bool>, label: String)` and `SegmentedPicker<Value: Hashable>(selection: Binding<Value>, options: [(label: String, value: Value)])` — Task 2 instantiates both exactly as written here.

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Panel-native monochrome controls (settings redesign). Stock control
/// styles (.checkbox, .radioGroup, .switch) tint system blue; the panel's
/// color law reserves color for meaning — status lamps, git refs — so
/// controls read as structure: Color.primary opacities only.

/// A 26×15 capsule switch. On: 92% primary track with a panel-background
/// knob; off: 16% primary track with a mid-primary knob. Both knob/track
/// pairs keep contrast in light and dark themes.
struct MiniSwitch: View {
    @Binding var isOn: Bool
    /// Accessibility only — the visible label lives in the settings row.
    let label: String

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(Color.primary.opacity(isOn ? 0.92 : 0.16))
                .frame(width: 26, height: 15)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn
                              ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                              : AnyShapeStyle(Color.primary.opacity(0.55)))
                        .padding(1.5)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}

/// A compact segmented pill (the sort control). Selection is a 18% primary
/// chip inside an 8% primary container — monochrome, never accent-tinted.
struct SegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(label: String, value: Value)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = selection == option.value
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(.system(size: 10.5, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(selected ? 0.18 : 0)))
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(1.5)
        .background(RoundedRectangle(cornerRadius: 6.5).fill(Color.primary.opacity(0.08)))
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!` (new file compiles; nothing references it yet)

- [ ] **Step 3: Regression tests**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed` — 333 tests, 0 failures

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/PanelControls.swift
git commit -m "feat: panel-native monochrome MiniSwitch and SegmentedPicker"
```

---

### Task 2: Rebuild SettingsPane as card groups

**Files:**
- Modify: `Sources/ClaudeLightApp/SettingsPane.swift` (full rewrite of the view body; keep the type name, `watcher`/`onBack` members, and `hasOAuthLogin` gate)

**Interfaces:**
- Consumes: `MiniSwitch(isOn:label:)` and `SegmentedPicker(selection:options:)` from Task 1; existing `SessionWatcher` published vars (`sessionOrder`, `showSubagents`, `showUsageStats`, `showPlanLimits`, `launchAtLoginEnabled`/`toggleLaunchAtLogin()`, `notifyOnNeedsYou`, `hooksInstalled`, `installHooks()`, `removeHooks()`, `hookActionError`); `SessionOrder.project/.opened`; `PanelPalette.red`.
- Produces: nothing new — `PanelContent` keeps instantiating `SettingsPane(watcher:onBack:)` unchanged.

- [ ] **Step 1: Replace the file contents**

Layout arithmetic (comment-worthy, keep these invariants): outer padding is 12 to match `PanelContent`, so full-width dividers align with the main view's. Cards span the 12-inset column; card content pads 10 more, landing text at 22 — the same content column the old pane used. Section titles indent 10 to sit on the card content edge.

```swift
import SwiftUI
import ClaudeLightCore

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
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Regression tests**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed` — 333 tests, 0 failures

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/SettingsPane.swift
git commit -m "feat: rebuild settings pane as titled card groups (variant B)"
```

---

### Task 3: Live verification and tuning

**Files:**
- Modify (tuning only, if the live look demands it): `Sources/ClaudeLightApp/SettingsPane.swift`, `Sources/ClaudeLightApp/PanelControls.swift`

**Interfaces:**
- Consumes: the built app; mockup variant B as the reference rendering.
- Produces: the shipped look; any tuning deltas committed.

- [ ] **Step 1: Build and relaunch the app**

Run: `scripts/package-app.sh && open "Claude Light.app"` (use the script's actual output path — check its tail for where the bundle lands)
Expected: menu bar icon appears; panel opens.

- [ ] **Step 2: Compare against mockup variant B, both themes**

Checklist (each against https://claude.ai/code/artifact/d9c90d4b-ed2d-4367-b6ef-90d39d88c38f):
- Three section titles + hooks card; titles wear the 9pt uppercase tertiary treatment.
- Cards match session-card surface; inset hairlines between rows.
- Switches: monochrome, knob contrast holds in dark AND light appearance.
- Sort segmented control: selection legible, taps switch order live (list regroups behind the pane).
- Captions align under labels, wrap inside the label column.
- Toggling each switch drives its real behavior (subagents rows, usage row, notifications prompt).
- Hooks card hover brightens; click still installs/removes hooks; error label renders red under the card (temporarily break `~/.claude/settings.json` permissions to see it, or skip if not cheap).
- Panel height: pane fits without scrolling at 340×(natural height).

- [ ] **Step 3: Live-tune in tiny steps**

Repo law: one knob per iteration (spacing, opacity, size), rebuild, re-glance with the user. Commit each accepted adjustment:

```bash
git add -A Sources/
git commit -m "fix: settings pane live-tuning (<what changed>)"
```

- [ ] **Step 4: Full test suite final pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed`
