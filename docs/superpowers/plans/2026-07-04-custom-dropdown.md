# Custom Dropdown Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the system menu with a custom SwiftUI panel — session cards with live timers and question subtitles, collapsible subagent rows, in-place settings — unlocking the UI roadmap (#86).

**Architecture:** `MenuBarExtra` switches from `.menu` to `.window` style; `MenuContent.swift` (and all its NSImage template workarounds) is deleted in favor of `PanelContent` + `SessionCard` + `SettingsPane`. All strings the panel renders are derived by pure, tested Core functions in a new `PanelModel.swift`. `SessionWatcher`, the icon, notifications, and the hook are untouched.

**Tech Stack:** Swift 5.9 (SwiftPM), SwiftUI (`MenuBarExtra .window`, `TimelineView`), XCTest.

**Spec:** `docs/superpowers/specs/2026-07-04-custom-dropdown-design.md`

## Global Constraints

- Work on branch `feat/custom-dropdown` (already created). Never commit to `main`.
- No AI attribution anywhere: no `Co-Authored-By` trailers, no "Generated with" footers.
- macOS 13 floor (`.window` style requires it; `LSMinimumSystemVersion` is already 13.0).
- Exact strings preserved from today: empty state `"No active Claude Code sessions"`; done row `"<name> — done · <age> ago"`; accessibility label `"<name> — <friendly label>"`; error subtitle `"API error: <reason>"`.
- Chip format exactly: `"⑂ N subagent(s)"` + `" · M failed"` only when M > 0 (singular noun when N == 1).
- Panel width 340 pt. Reserved stats slot = the divider above the footer (nothing renders there in this project).
- Subagent collapse state: per-card, in-memory, default expanded. No persistence.
- Run `swift test` (zero failures) and `swift build` before each commit.
- Do NOT touch `/Applications/Claude Light.app` except in Task 5's controlled swap.

---

### Task 1: Core `PanelModel` — tested string derivations

**Files:**
- Create: `Sources/ClaudeLightCore/PanelModel.swift`
- Test: `Tests/ClaudeLightCoreTests/PanelModelTests.swift` (new file)

**Interfaces:**
- Consumes: existing Core — `displayName(for:)`, `friendlyStatusLabel(for:)`, `relativeTime(secondsAgo:)`, `Session`, `SubagentList`/`Subagent`.
- Produces (Tasks 2–4 render these verbatim):
  - `public func cardTitle(for session: Session) -> String`
  - `public func cardSubtitle(for session: Session, errorReason: String?) -> String?`
  - `public func timerText(for session: Session, now: Date) -> String`
  - `public func doneRowText(for session: Session, now: Date) -> String`
  - `public func subagentChipText(_ list: SubagentList) -> String`
  - `public func accessibilityLabel(for session: Session) -> String`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeLightCoreTests/PanelModelTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class PanelModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func s(_ status: SessionStatus, detail: String? = nil,
                   ageSeconds: TimeInterval = 0, cwd: String = "/x/vatios") -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: "vatios", cwd: cwd,
                updatedAt: now.addingTimeInterval(-ageSeconds), detail: detail)
    }

    func test_cardTitle_isDisplayName() {
        XCTAssertEqual(cardTitle(for: s(.running)), "vatios")
    }

    func test_cardSubtitle_detailWinsOverLabel() {
        XCTAssertEqual(cardSubtitle(for: s(.attention, detail: "Deploy where?"), errorReason: nil),
                       "Deploy where?")
    }

    func test_cardSubtitle_fallsBackToFriendlyLabel() {
        XCTAssertEqual(cardSubtitle(for: s(.attention), errorReason: nil), "awaiting your reply")
        XCTAssertEqual(cardSubtitle(for: s(.running), errorReason: nil), "running")
    }

    func test_cardSubtitle_errorBeatsDetail() {
        XCTAssertEqual(cardSubtitle(for: s(.error, detail: "stale"), errorReason: "rate limited"),
                       "API error: rate limited")
        XCTAssertEqual(cardSubtitle(for: s(.error), errorReason: nil), "API error: api error")
    }

    func test_cardSubtitle_doneIsNil() {
        XCTAssertNil(cardSubtitle(for: s(.done), errorReason: nil))
    }

    func test_timerText_formatsAge() {
        XCTAssertEqual(timerText(for: s(.attention, ageSeconds: 720), now: now), "12m")
        XCTAssertEqual(timerText(for: s(.running, ageSeconds: 45), now: now), "45s")
    }

    func test_doneRowText_matchesMenuWording() {
        XCTAssertEqual(doneRowText(for: s(.done, ageSeconds: 40), now: now),
                       "vatios — done · 40s ago")
    }

    func test_subagentChipText_pluralAndFailed() {
        let list = SubagentList(visible: [
            Subagent(id: "1", label: "a", state: .running),
            Subagent(id: "2", label: "b", state: .failed),
            Subagent(id: "3", label: "c", state: .running),
        ], overflowRunning: 1)
        XCTAssertEqual(subagentChipText(list), "⑂ 4 subagents · 1 failed")
    }

    func test_subagentChipText_singularNoFailures() {
        let list = SubagentList(visible: [Subagent(id: "1", label: "a", state: .running)],
                                overflowRunning: 0)
        XCTAssertEqual(subagentChipText(list), "⑂ 1 subagent")
    }

    func test_accessibilityLabel_matchesOldMenuRow() {
        XCTAssertEqual(accessibilityLabel(for: s(.waiting)), "vatios — waiting for permission")
    }
}
```

(Check `Subagent`'s memberwise init order in `Sources/ClaudeLightCore/SubagentDetection.swift:4-8` — `id`, `label`, `state` — before assuming; adjust the test if it differs.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'cardTitle' in scope` (etc.).

- [ ] **Step 3: Implement**

Create `Sources/ClaudeLightCore/PanelModel.swift`:

```swift
import Foundation

// Pure derivations for the panel UI (#86) — every string the SwiftUI layer
// renders verbatim, kept here so it is testable without a view hierarchy.

/// Card title: the project display name. Branch labels join here when #82 lands.
public func cardTitle(for session: Session) -> String {
    displayName(for: session)
}

/// Card subtitle: what the session is blocked on or doing.
/// Precedence: error reason > detail (#80) > friendly label. Done rows have
/// no subtitle (they render as a single flat line).
public func cardSubtitle(for session: Session, errorReason: String?) -> String? {
    switch session.status {
    case .done:
        return nil
    case .error:
        return "API error: \(errorReason ?? "api error")"
    default:
        return session.detail ?? friendlyStatusLabel(for: session.status)
    }
}

/// Elapsed-state timer for the card's trailing edge ("12m").
public func timerText(for session: Session, now: Date) -> String {
    relativeTime(secondsAgo: now.timeIntervalSince(session.updatedAt))
}

/// Flat done-row text — same wording the menu used (#54).
public func doneRowText(for session: Session, now: Date) -> String {
    let age = relativeTime(secondsAgo: now.timeIntervalSince(session.updatedAt))
    return "\(displayName(for: session)) — done · \(age) ago"
}

/// Collapsed-subagents chip: "⑂ 3 subagents · 1 failed".
public func subagentChipText(_ list: SubagentList) -> String {
    let total = list.visible.count + list.overflowRunning
    let noun = total == 1 ? "subagent" : "subagents"
    let failed = list.visible.filter { $0.state == .failed }.count
    return failed > 0 ? "⑂ \(total) \(noun) · \(failed) failed" : "⑂ \(total) \(noun)"
}

/// VoiceOver label for a card — the wording the old menu rows carried, so
/// the panel migration doesn't regress accessibility.
public func accessibilityLabel(for session: Session) -> String {
    "\(displayName(for: session)) — \(friendlyStatusLabel(for: session.status))"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: all pass (count grows by 10).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/PanelModel.swift Tests/ClaudeLightCoreTests/PanelModelTests.swift
git commit -m "feat: PanelModel string derivations for the custom panel (#86)"
```

---

### Task 2: `SessionCard` + `SubagentRows` + palette

**Files:**
- Create: `Sources/ClaudeLightApp/SessionCard.swift`

**Interfaces:**
- Consumes: Task 1's PanelModel functions; Core `needsYou(_:)`, `SubagentList`; `TerminalFocuser.focus(_:)` (existing).
- Produces: `struct SessionCard: View` with init `(session: Session, errorReason: String?, subagents: SubagentList?, now: Date)`; `enum PanelPalette` with `static let red/orange/green: Color` and `static func color(for: SessionStatus) -> Color`. Task 4 instantiates SessionCard per session.

- [ ] **Step 1: Create the file**

Create `Sources/ClaudeLightApp/SessionCard.swift` with exactly:

```swift
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
        case .done: return Color.secondary
        }
    }
}

/// One session in the panel: a clickable card (status dot, title, live
/// timer, subtitle with the pending question) with collapsible subagent
/// rows. Done sessions render as a flat, non-interactive grey line (#54).
struct SessionCard: View {
    let session: Session
    let errorReason: String?
    let subagents: SubagentList?
    let now: Date

    /// Per-card, in-memory only — resets on relaunch by design.
    @State private var subagentsCollapsed = false
    @State private var hovering = false

    var body: some View {
        if session.status == .done {
            doneRow
        } else {
            card
        }
    }

    private var doneRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(doneRowText(for: session, now: now))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClaudeLightCore.accessibilityLabel(for: session))
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
        .accessibilityLabel(ClaudeLightCore.accessibilityLabel(for: session))
        .accessibilityAddTraits(.isButton)
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
            .accessibilityLabel(collapsed ? "expand subagents" : "collapse subagents")

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
```

Note: `accessibilityLabel(for:)` is Core's free function; inside a View, `accessibilityLabel` collides with the modifier name, hence the `ClaudeLightCore.` qualification at the two call sites.

- [ ] **Step 2: Build and run the suite**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: `Build complete!`, all tests pass (the new views are unused until Task 4 — an `unused` warning is acceptable, compile errors are not).

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/SessionCard.swift
git commit -m "feat: session card and collapsible subagent rows for the panel (#86)"
```

---

### Task 3: `SettingsPane`

**Files:**
- Create: `Sources/ClaudeLightApp/SettingsPane.swift`

**Interfaces:**
- Consumes: `SessionWatcher`'s published API — `showSubagents` (read-write), `launchAtLoginAvailable`/`launchAtLoginEnabled`/`toggleLaunchAtLogin()`, `notificationsAvailable`/`notifyOnNeedsYou` (read-write), `hooksInstalled`/`installHooks()`/`removeHooks()`/`hookActionError`; `PanelPalette` (Task 2).
- Produces: `struct SettingsPane: View` with init `(watcher: SessionWatcher, onBack: @escaping () -> Void)`. Task 4 flips to it.

- [ ] **Step 1: Create the file**

Create `Sources/ClaudeLightApp/SettingsPane.swift` with exactly:

```swift
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
```

- [ ] **Step 2: Build and run the suite**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: `Build complete!`, all tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/SettingsPane.swift
git commit -m "feat: in-place settings pane for the panel (#86)"
```

---

### Task 4: `PanelContent`, `.window` wiring, delete `MenuContent`

**Files:**
- Create: `Sources/ClaudeLightApp/PanelContent.swift`
- Modify: `Sources/ClaudeLightApp/ClaudeLightApp.swift:21-33` (content view + style)
- Delete: `Sources/ClaudeLightApp/MenuContent.swift`

**Interfaces:**
- Consumes: `SessionCard` (Task 2), `SettingsPane` (Task 3), `PanelPalette`; `SessionWatcher` published state; Core `summaryText` output via `watcher.summary`.
- Produces: `struct PanelContent: View` with init `(watcher: SessionWatcher)` — the MenuBarExtra content.

- [ ] **Step 1: Create `PanelContent.swift`**

```swift
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
```

- [ ] **Step 2: Rewire the app scene**

In `Sources/ClaudeLightApp/ClaudeLightApp.swift`, change the scene body:

```swift
        MenuBarExtra {
            PanelContent(watcher: watcher)
        } label: {
```

(the label closure stays exactly as is) and the style line:

```swift
        .menuBarExtraStyle(.window)
```

- [ ] **Step 3: Delete `MenuContent.swift`**

```bash
git rm Sources/ClaudeLightApp/MenuContent.swift
```

- [ ] **Step 4: Build and run the suite**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: `Build complete!` (no dangling MenuContent references), all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A Sources/ClaudeLightApp/
git commit -m "feat: replace the system menu with the custom panel (#86)"
```

---

### Task 5: End-to-end verification (signed swap)

**Files:** none (verification only)

**Interfaces:**
- Consumes: the complete branch (Tasks 1–4).

This is a controller/user task — the panel is visual and interactive. Flow (same as the v0.12.0 local update):

- [ ] **Step 1: Build, sign, swap**

```bash
bash scripts/package-app.sh >/dev/null 2>&1
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Fernando Castillo (7MTZYB93KB)" \
  "dist/Claude Light.app/Contents/MacOS/claude-light-hook" \
  "dist/Claude Light.app/Contents/MacOS/ClaudeLightApp"
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Fernando Castillo (7MTZYB93KB)" "dist/Claude Light.app"
osascript -e 'quit app "Claude Light"'; sleep 2
open "dist/Claude Light.app"
```

(Runs the dist copy directly — do NOT overwrite /Applications during verification; the user's install is restored by relaunching it in Step 3.)

- [ ] **Step 2: Drive every state with fake sessions and verify visually**

Write fake session files under `~/.claude-light/sessions/` (running → attention-with-detail; a running session while a real transcript has subagents is hard to fake — instead verify subagent rendering with this session's own live data if available). Checklist to verify with the user:

- Needs-you card: red dot, question subtitle, red timer counting up live (1 s ticks).
- Running card: orange dot, hover highlight, click focuses the terminal.
- Subagent block: expanded rows, chevron collapses to the "⑂ N subagents" chip, failed shown red (if a live fan-out exists; otherwise defer to real usage).
- Done row: flat grey checkmark line, non-interactive.
- Empty state: remove all fake files → "No active Claude Code sessions".
- Settings: gear flips in place; all toggles work; Back returns; version + Quit in footer.
- Outside click dismisses the panel; reopening shows fresh state.

- [ ] **Step 3: Clean up**

```bash
osascript -e 'quit app "Claude Light"'; sleep 1
pkill -f "dist/Claude Light.app" 2>/dev/null
rm -f ~/.claude-light/sessions/panel-e2e*.json
open "/Applications/Claude Light.app"
```

Record observations; no commit.

---

## After all tasks

Push and open the PR: title `feat: custom dropdown panel`, body with before/after, `Closes #86`. Screenshot the panel during Task 5 for the PR body and the future README/#85 material.
