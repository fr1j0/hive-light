# Settings-in-Header + Footer Rebalance (#109) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Settings control from the panel footer to the trailing corner of an always-on header row (gear icon only), and rebalance the footer (app name + version left, power button right).

**Architecture:** View-only change confined to `Sources/ClaudeLightApp/PanelContent.swift`. The header row becomes unconditional, gains the gear button, and shows a "No active sessions" fallback when `watcher.summary` is nil; the body's duplicate empty-state text is removed; the footer swaps its left/right clusters.

**Tech Stack:** SwiftUI (macOS MenuBarExtra `.window` panel), Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-07-05-settings-header-design.md`

## Global Constraints

- Only `Sources/ClaudeLightApp/PanelContent.swift` may change. No `ClaudeLightCore` changes.
- The existing full test suite (276 tests) must pass unmodified — `swift test`.
- Panel width stays `340` (`.frame(width: 340)` in `body`) — do not touch.
- Idle-header fallback copy is exactly: `No active sessions`.
- Gear accessibility label is exactly `Settings`; tooltip via `.help("Settings")`.
- There are no view snapshot tests in this repo; each task's gate is `swift build` + full-suite regression. Live/manual verification happens after both tasks (tooltips cannot be exercised synthetically — human hover only).

---

### Task 1: Always-on header with gear; remove body empty-state text

**Files:**
- Modify: `Sources/ClaudeLightApp/PanelContent.swift:44-90` (`sessionList` and `sessionRows`)

**Interfaces:**
- Consumes: existing `watcher.summary: String?` (nil = no live sessions), existing `headerColor: Color` computed property (already returns `Color.secondary` when no icon segment is lit), existing `@State showingSettings`.
- Produces: nothing new for later tasks — Task 2 touches only the separate `footer` property.

- [ ] **Step 1: Replace the conditional header with an always-on header containing the gear**

In `sessionList(now:)`, replace this block:

```swift
            if let summary = watcher.summary {
                HStack(spacing: 8) {
                    Circle().fill(headerColor).frame(width: 8, height: 8)
                    Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                Divider()
            }
```

with:

```swift
            HStack(spacing: 8) {
                Circle().fill(headerColor).frame(width: 8, height: 8)
                Text(watcher.summary ?? "No active sessions")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Settings")
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            Divider()
```

Notes for the implementer:
- `headerColor` needs no change — it already falls back to `Color.secondary` (grey) when no sessions are live.
- The `.frame(width: 22, height: 22)` + `.contentShape(Rectangle())` go on the **label** (`Image`), padding the tap area beyond the glyph.
- `Spacer()` pushes the gear to the trailing edge; the dot + text stay left.

- [ ] **Step 2: Remove the body's empty-state text**

In `sessionRows(now:)`, replace:

```swift
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
```

with:

```swift
        VStack(alignment: .leading, spacing: 4) {
            ForEach(watcher.sessions, id: \.sessionID) { session in
                SessionCard(session: session,
                            errorReason: watcher.errorReasons[session.sessionID],
                            subagents: watcher.subagentsBySession[session.sessionID],
                            now: now)
            }
        }
```

With zero sessions this renders nothing; the outer `VStack(spacing: 4)` puts the header divider and footer divider a few points apart, reading as a quiet empty band (per spec — an optional ~6pt spacer is a live-build visual call, deferred to manual verification).

- [ ] **Step 3: Build and run the full suite**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Build complete!` and `Executed 276 tests, with 0 failures`

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/PanelContent.swift
git commit -m "feat: always-on header with icon-only Settings gear (#109)"
```

---

### Task 2: Footer rebalance — name + version left, power right

**Files:**
- Modify: `Sources/ClaudeLightApp/PanelContent.swift:92-123` (`footer` property; line numbers shift slightly after Task 1)

**Interfaces:**
- Consumes: existing `Self.appVersion: String?`, `watcher.hookActionError: String?`, `PanelPalette.red`.
- Produces: nothing — final task.

- [ ] **Step 1: Rebalance the footer clusters**

Replace the entire `footer` property body:

```swift
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
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
    }
```

with:

```swift
    private var footer: some View {
        HStack(spacing: 8) {
            if let version = Self.appVersion {
                Text("Claude Light v\(version)").font(.system(size: 11)).foregroundStyle(.tertiary)
            }

            // A failed hook install stays visible without opening Settings.
            if let hookError = watcher.hookActionError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(PanelPalette.red)
                    .help(hookError)
                    .accessibilityLabel(hookError)
            }

            Spacer()

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
```

The Settings button is deleted (it now lives in the header, added in Task 1); the version text moves to the left cluster with the hook-error warning beside it; the power button keeps the right edge.

- [ ] **Step 2: Build and run the full suite**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Build complete!` and `Executed 276 tests, with 0 failures`

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/PanelContent.swift
git commit -m "feat: footer rebalance — name+version left, power right (#109)"
```

---

### Manual verification (after both tasks, human-driven)

Build and run the menu bar app locally, then check:

1. **Zero sessions:** header shows grey dot + "No active sessions" with gear at top-right; no duplicate empty text in the body; empty band between dividers doesn't read as a heavy double rule (if it does, add `Spacer().frame(height: 6)` in the empty case).
2. **Active sessions:** colored dot + summary in header, gear at top-right.
3. **Gear:** hover shows the "Settings" tooltip (human hover — synthetic events don't trigger tracking areas); click flips to `SettingsPane`; Done flips back.
4. **Footer:** "Claude Light vX.Y.Z" at left (warning triangle beside it if a hook error is forced), power at right; power still quits.
