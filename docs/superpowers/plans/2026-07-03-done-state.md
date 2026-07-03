# Brief "Done" State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ended sessions linger ~2 minutes as a greyed-out, non-interactive "done · 40s ago" row instead of vanishing instantly (#54).

**Architecture:** Tombstone on disk — `SessionEnd` writes the session file with a new `done` status instead of deleting it. Pure Core functions decide linger expiry and visibility; `SessionWatcher.reload()` deletes expired tombstones and excludes done sessions from the light/summary; `MenuContent` renders done rows as non-interactive labels. No new timers — the existing 30 s stale timer picks up expiry.

**Tech Stack:** Swift 5.9 (SwiftPM), XCTest, SwiftUI/AppKit menu-bar app.

**Spec:** `docs/superpowers/specs/2026-07-03-done-state-design.md`

## Global Constraints

- Work on branch `feat/done-state` (already created). Never commit to `main`.
- No AI attribution anywhere: no `Co-Authored-By` trailers, no "Generated with" footers in commits or PRs.
- New status raw value is exactly `"done"`; linger constant is exactly `doneLingerWindow: TimeInterval = 120`.
- Done sessions must not affect `aggregateLight`, `aggregateNeedsAttention`, `statusCounts`, or `summaryText` outputs — exclusion happens at the call sites in `SessionWatcher.reload()`.
- Run the full suite with `swift test` before each commit; all tests must pass (zero failures).
- Do NOT touch `/Applications/Claude Light.app` (it's a locally-signed build; replacing it breaks notification registration).

---

### Task 1: `done` status in the data model, hook mapping, and every status switch

**Files:**
- Modify: `Sources/ClaudeLightCore/Session.swift:3-10` (enum)
- Modify: `Sources/ClaudeLightCore/HookAction.swift` (SessionEnd mapping; remove `.delete`)
- Modify: `Sources/ClaudeLightCore/ApplyHook.swift` (remove `.delete` branch)
- Modify: `Sources/ClaudeLightCore/NeedsYouDetection.swift` (two switches)
- Modify: `Sources/ClaudeLightCore/MenuModel.swift` (two switches)
- Modify: `Sources/ClaudeLightApp/MenuContent.swift:194-200` (`color(for:)` switch — compile fix only; real rendering is Task 4)
- Test: `Tests/ClaudeLightCoreTests/HookActionTests.swift`, `Tests/ClaudeLightCoreTests/ApplyHookTests.swift`, `Tests/ClaudeLightCoreTests/NeedsYouDetectionTests.swift`, `Tests/ClaudeLightCoreTests/MenuModelTests.swift`

**Interfaces:**
- Produces: `SessionStatus.done` (raw `"done"`); `action(for:)` maps `"SessionEnd"` → `.set(.done)`; `HookAction` no longer has a `.delete` case; `needsYou(.done) == false`; `friendlyStatusLabel(for: .done) == "done"`; `sortedForMenu` ranks `.done` last (6). Tasks 2–4 rely on the `.done` case existing.

- [ ] **Step 1: Write the failing tests**

In `Tests/ClaudeLightCoreTests/HookActionTests.swift`, replace `test_sessionEnd_deletes` (lines 40-42) with:

```swift
    func test_sessionEnd_setsDone() {
        XCTAssertEqual(action(for: payload("SessionEnd")), .set(.done))
    }
```

In `Tests/ClaudeLightCoreTests/ApplyHookTests.swift`, replace `test_deleteAction_removesSession` (lines 30-35) with:

```swift
    func test_sessionEnd_writesDoneTombstone_preservingTerminalIdentity() throws {
        let store = tempStore()
        let terminal = TerminalContext(termProgram: "WarpTerminal", tty: "ttys001",
                                       termSessionId: nil, focusURL: "warp://session/abc")
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now, terminal: terminal)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "SessionEnd", cwd: "/x/p", message: nil),
                      to: store, now: now.addingTimeInterval(60))
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(s.status, .done)
        XCTAssertEqual(s.updatedAt, now.addingTimeInterval(60))
        XCTAssertEqual(s.termProgram, "WarpTerminal")
        XCTAssertEqual(s.focusURL, "warp://session/abc")
    }
```

(Check `TerminalContext`'s memberwise init in `Sources/ClaudeLightCore/TerminalContext.swift` first; if the parameter order differs, match it — the assertion payload is what matters.)

In `Tests/ClaudeLightCoreTests/NeedsYouDetectionTests.swift`, add:

```swift
    func test_done_isNotNeedsYou() {
        XCTAssertFalse(needsYou(.done))
    }

    func test_runningToDone_isNotNewlyNeedingYou() {
        let session = Session(sessionID: "s1", status: .done, project: "p", cwd: "/p",
                              updatedAt: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertTrue(newlyNeedingYou(previous: ["s1": .running], current: [session]).isEmpty)
    }

    func test_friendlyStatusLabel_done() {
        XCTAssertEqual(friendlyStatusLabel(for: .done), "done")
    }
```

In `Tests/ClaudeLightCoreTests/MenuModelTests.swift`, add:

```swift
    func test_sortedForMenu_ranksDoneLast() {
        func s(_ id: String, _ status: SessionStatus) -> Session {
            Session(sessionID: id, status: status, project: id, cwd: "/p",
                    updatedAt: Date(timeIntervalSince1970: 1_000_000))
        }
        let sorted = sortedForMenu([s("a", .done), s("b", .idle), s("c", .running)])
        XCTAssertEqual(sorted.map(\.sessionID), ["c", "b", "a"])
    }

    func test_statusCounts_ignoresDone() {
        func s(_ status: SessionStatus) -> Session {
            Session(sessionID: UUID().uuidString, status: status, project: "p", cwd: "/p",
                    updatedAt: Date(timeIntervalSince1970: 1_000_000))
        }
        let counts = statusCounts(for: [s(.done), s(.running)])
        XCTAssertEqual(counts, StatusCounts(needYou: 0, working: 1, idle: 0, error: 0))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: compile FAILURE — `type 'SessionStatus' has no member 'done'` (the enum case doesn't exist yet; compile failure is this step's RED).

- [ ] **Step 3: Implement**

`Sources/ClaudeLightCore/Session.swift` — add the case after `error`:

```swift
public enum SessionStatus: String, Codable, Sendable {
    case running
    case waiting
    case attention
    case handoff
    case idle
    case error
    case done
}
```

`Sources/ClaudeLightCore/HookAction.swift` — remove the `.delete` case from the enum and remap SessionEnd:

```swift
public enum HookAction: Equatable, Sendable {
    case set(SessionStatus)
    case ignore
}
```

and in `action(for:)` replace:

```swift
    case "SessionEnd":
        return .delete
```

with:

```swift
    case "SessionEnd":
        // Tombstone, not delete: the row lingers briefly as "done" (#54).
        // The app removes the file after doneLingerWindow.
        return .set(.done)
```

`Sources/ClaudeLightCore/ApplyHook.swift` — delete the branch:

```swift
    case .delete:
        try store.delete(sessionID: payload.sessionID)
```

`Sources/ClaudeLightCore/NeedsYouDetection.swift` — extend both switches:

```swift
public func needsYou(_ status: SessionStatus) -> Bool {
    switch status {
    case .waiting, .attention, .handoff, .error: return true
    case .running, .idle, .done: return false
    }
}
```

and in `friendlyStatusLabel(for:)` add:

```swift
    case .done: return "done"
```

`Sources/ClaudeLightCore/MenuModel.swift` — in `statusCounts(for:)` add to the switch:

```swift
        case .done: break   // linger rows count nowhere ("as if absent", #54)
```

and in `sortedForMenu`'s `rank`:

```swift
        case .done: return 6
```

`Sources/ClaudeLightApp/MenuContent.swift` — in `color(for:)` add (placeholder until Task 4's dedicated rendering; done rows won't reach the dot path once Task 4 lands):

```swift
        case .done: return .secondaryLabelColor
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, zero failures. Also: `swift build 2>&1 | tail -2` → `Build complete!` (proves the App target's switch is exhaustive too).

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: SessionEnd writes a done tombstone instead of deleting (#54)"
```

---

### Task 2: Linger window, expiry partition, and headless-done visibility

**Files:**
- Modify: `Sources/ClaudeLightCore/Aggregate.swift` (constant + function, next to `liveSessions`)
- Modify: `Sources/ClaudeLightCore/HeadlessSessions.swift:12-14` (`visibleSessions`)
- Test: `Tests/ClaudeLightCoreTests/AggregateTests.swift`, `Tests/ClaudeLightCoreTests/HeadlessSessionTests.swift`

**Interfaces:**
- Consumes: `SessionStatus.done` (Task 1).
- Produces: `public let doneLingerWindow: TimeInterval = 120`; `public func expiredDoneSessions(_ sessions: [Session], now: Date, linger: TimeInterval = doneLingerWindow) -> [Session]` (returns the done sessions older than `linger`; never returns non-done sessions); `visibleSessions` additionally drops done+headless. Task 3 calls both.

- [ ] **Step 1: Write the failing tests**

In `Tests/ClaudeLightCoreTests/AggregateTests.swift` (note the existing helpers at the top of the class: `s(_:ageSeconds:)` builds a session aged relative to `now = Date(timeIntervalSince1970: 1_000_000)`):

```swift
    func test_expiredDoneSessions_keepsYoungDone() {
        XCTAssertTrue(expiredDoneSessions([s(.done, ageSeconds: 60)], now: now).isEmpty)
    }

    func test_expiredDoneSessions_returnsOldDone() {
        let old = s(.done, ageSeconds: 121)
        XCTAssertEqual(expiredDoneSessions([old, s(.done, ageSeconds: 10)], now: now).map(\.sessionID),
                       [old.sessionID])
    }

    func test_expiredDoneSessions_neverReturnsNonDone() {
        XCTAssertTrue(expiredDoneSessions([s(.idle, ageSeconds: 10_000), s(.running, ageSeconds: 10_000)],
                                          now: now).isEmpty)
    }
```

In `Tests/ClaudeLightCoreTests/HeadlessSessionTests.swift` (check the top of that file for its session helper; if none fits, build sessions inline as below — headless means `tty == nil && focusURL == nil`):

```swift
    func test_visibleSessions_hidesDoneHeadless() {
        let doneHeadless = Session(sessionID: "h", status: .done, project: "p", cwd: "/p",
                                   updatedAt: Date(timeIntervalSince1970: 1_000_000))
        let doneReachable = Session(sessionID: "r", status: .done, project: "p", cwd: "/p",
                                    updatedAt: Date(timeIntervalSince1970: 1_000_000), tty: "ttys001")
        XCTAssertEqual(visibleSessions([doneHeadless, doneReachable]).map(\.sessionID), ["r"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'expiredDoneSessions' in scope` (and, once that exists, the visibility test fails with the done+headless row still visible).

- [ ] **Step 3: Implement**

`Sources/ClaudeLightCore/Aggregate.swift` — add below `liveSessions`:

```swift
/// How long a finished session lingers as a "done" row before its tombstone
/// file is removed (#54). Expiry is re-checked by the app's 30 s stale timer,
/// so rows live doneLingerWindow..+30 s in practice.
public let doneLingerWindow: TimeInterval = 120

/// The done sessions whose linger window has elapsed — the app deletes their
/// files and drops them from display. Non-done sessions never expire here.
public func expiredDoneSessions(_ sessions: [Session], now: Date,
                                linger: TimeInterval = doneLingerWindow) -> [Session] {
    sessions.filter { $0.status == .done && now.timeIntervalSince($0.updatedAt) > linger }
}
```

`Sources/ClaudeLightCore/HeadlessSessions.swift` — replace `visibleSessions` and its doc comment:

```swift
/// Drops the rows that are pure noise: headless sessions that are idle or
/// done. A *live* headless job (running, or somehow blocked) is still worth
/// seeing; a finished or parked one has nothing to reach and nothing pending.
public func visibleSessions(_ sessions: [Session]) -> [Session] {
    sessions.filter { !(($0.status == .idle || $0.status == .done) && isHeadless($0)) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, zero failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: done-linger expiry partition and headless-done visibility (#54)"
```

---

### Task 3: SessionWatcher wiring — delete expired tombstones, exclude done from light/summary

**Files:**
- Modify: `Sources/ClaudeLightApp/SessionWatcher.swift:134-183` (`reload()`)

**Interfaces:**
- Consumes: `expiredDoneSessions(_:now:)`, `doneLingerWindow` (Task 2); `SessionStore.delete(sessionID:)` (existing).
- Produces: `watcher.sessions` may now contain `.done` rows (Task 4 renders them); `watcher.icon` / `watcher.summary` computed from non-done sessions only.

- [ ] **Step 1: Modify `reload()`**

The method currently begins (SessionWatcher.swift:134-136):

```swift
    func reload() {
        let all = (try? store.loadAll()) ?? []
        var live = liveSessions(all, now: Date())
```

Replace those first lines with:

```swift
    func reload() {
        let all = (try? store.loadAll()) ?? []
        let now = Date()
        var live = liveSessions(all, now: now)
        // Done tombstones past their linger window: remove the file and the row.
        let expired = Set(expiredDoneSessions(live, now: now).map(\.sessionID))
        for id in expired { try? store.delete(sessionID: id) }
        live.removeAll { expired.contains($0.sessionID) }
```

and at the tail of `reload()` (currently lines 180-182):

```swift
        let state = iconState(for: sorted)
        self.icon = state
        self.summary = summaryText(for: statusCounts(for: sorted))
```

replace with:

```swift
        // Done rows are display-only: the light and header behave as if the
        // session were gone (#54).
        let active = sorted.filter { $0.status != .done }
        let state = iconState(for: active)
        self.icon = state
        self.summary = summaryText(for: statusCounts(for: active))
```

Leave everything between untouched — in particular the error-scan loop (`for i in live.indices where live[i].status == .running`) already skips done sessions, and `lastStatuses`/`newlyNeedingYou` are safe because `needsYou(.done) == false` (pinned by Task 1's tests).

- [ ] **Step 2: Build and run the full suite**

Run: `swift build 2>&1 | tail -2 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, all tests PASS. (This task has no unit tests of its own — the logic it wires is covered by Task 1–2's Core tests; the app target has no test target.)

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/SessionWatcher.swift
git commit -m "feat: linger done rows in the menu, expire their tombstones (#54)"
```

---

### Task 4: MenuContent — greyed, non-interactive done row with checkmark and age

**Files:**
- Modify: `Sources/ClaudeLightApp/MenuContent.swift:22-34` (row loop) and the helpers section (~line 150)

**Interfaces:**
- Consumes: `.done` rows in `watcher.sessions` (Task 3); `relativeTime(secondsAgo:)` and `displayName(for:)` from ClaudeLightCore (existing).

- [ ] **Step 1: Implement the done row**

In the `ForEach(watcher.sessions, ...)` loop (MenuContent.swift:22), the session row is currently one `Button`. Wrap it so done sessions render a non-interactive label instead (same pattern as the subagent rows at lines 36-48, which are already plain `Label`s):

```swift
            ForEach(watcher.sessions, id: \.sessionID) { session in
                if session.status == .done {
                    // Finished session lingering (#54): non-interactive — the
                    // terminal may already be gone.
                    Label {
                        Text(doneRowText(for: session))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(nsImage: Self.doneCheckmark)
                    }
                } else {
                    Button {
                        TerminalFocuser.focus(session)
                    } label: {
                        Label {
                            Text(rowText(for: session))
                        } icon: {
                            if session.status == .error {
                                Image(nsImage: Self.warningTriangle())
                            } else {
                                Image(nsImage: Self.dot(color(for: session.status)))
                            }
                        }
                    }
                }
```

(The existing subagent `ForEach` and overflow rows that follow the Button stay exactly where they are, inside the outer `ForEach` — only the Button gets wrapped in the `if/else`.)

Add the helpers near `rowText(for:)` (~line 186):

```swift
    private func doneRowText(for session: Session) -> String {
        let age = relativeTime(secondsAgo: Date().timeIntervalSince(session.updatedAt))
        return "\(displayName(for: session)) — done · \(age) ago"
    }
```

and near the icon builders (~line 150), a grey non-template checkmark matching the dot/triangle conventions (menus coerce template images to mono, hence `isTemplate = false`):

```swift
    /// Grey `checkmark.circle.fill` for done rows, non-template like the dots.
    private static let doneCheckmark: NSImage = {
        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let base = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "done")?
            .withSymbolConfiguration(cfg) ?? NSImage()
        let out = NSImage(size: base.size)
        out.lockFocus()
        base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.secondaryLabelColor.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }()
```

- [ ] **Step 2: Build and run the full suite**

Run: `swift build 2>&1 | tail -2 && swift test 2>&1 | tail -3`
Expected: `Build complete!`, all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/MenuContent.swift
git commit -m "feat: render done sessions as greyed checkmark rows (#54)"
```

---

### Task 5: End-to-end verification with the debug binary

**Files:** none (verification only)

**Interfaces:**
- Consumes: the complete branch (Tasks 1–4).

Do NOT quit or replace `/Applications/Claude Light.app`. The debug binary runs alongside it as a second menu-bar icon; the two apps share `~/.claude-light/sessions/`, so drive the test with a throwaway session ID and clean it up.

- [ ] **Step 1: Launch the debug build**

```bash
swift build 2>&1 | tail -1
.build/debug/ClaudeLightApp & echo "debug pid: $!"
```

Expected: a second traffic-light icon appears in the menu bar.

- [ ] **Step 2: Simulate a session ending**

```bash
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > ~/.claude-light/sessions/done-e2e.json <<EOF
{"cwd":"/tmp/done-e2e","status":"running","updated_at":"$NOW","session_id":"done-e2e","project":"done-e2e","tty":"ttys999"}
EOF
sleep 3
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > ~/.claude-light/sessions/done-e2e.json <<EOF
{"cwd":"/tmp/done-e2e","status":"done","updated_at":"$NOW","session_id":"done-e2e","project":"done-e2e","tty":"ttys999"}
EOF
```

Verify in the DEBUG app's menu (the new icon): the `done-e2e` row shows greyed with a checkmark, reading `done-e2e — done · Ns ago`; clicking it does nothing; the aggregate light/header ignores it (with no other sessions: dim light, no summary header). Note: this session (`claude-light` running this plan) also appears — that's expected; judge only the `done-e2e` row and remember the light also reflects the real session.

- [ ] **Step 3: Verify expiry deletes the tombstone**

```bash
sleep 160 && ls ~/.claude-light/sessions/done-e2e.json
```

Expected: `ls: ... No such file or directory` — the linger window (120 s) plus one 30 s timer tick elapsed and the app deleted the file, and the row is gone from the debug app's menu.

- [ ] **Step 4: Clean up**

```bash
kill %1 2>/dev/null || pkill -f ".build/debug/ClaudeLightApp"
rm -f ~/.claude-light/sessions/done-e2e.json
```

Expected: the second menu-bar icon disappears. Record the observed behaviors in the task report; no commit (nothing changed).

---

## After all tasks

Push and open the PR (controller/user step): title `feat: brief done state for ended sessions`, body summarizing tombstone design + linger + verification, `Closes #54`.
