# Branch Labels Implementation Plan (#82)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Session cards title as `project — branch` when the session's cwd is a git checkout on a branch.

**Architecture:** The hook side (ClaudeLightCore's `applyHook`) discovers the branch by walking from the payload's cwd to the nearest `.git`, reading HEAD directly — one file read per level, never a subprocess (#43). The branch persists in the session JSON; `displayName(for:)` renders it. Spec: `docs/superpowers/specs/2026-07-05-branch-labels-design.md`.

**Tech Stack:** Swift 5 / Foundation, XCTest, swift test.

## Global Constraints

- No subprocess in any hook code path (hook perf, #43).
- New session-JSON key is `branch`; absent key must decode (old hooks) and be ignored by old apps (additive only).
- Merge semantics: payload HAS cwd → fresh `gitBranch` result wins, including nil; payload has NO cwd → stored value survives.
- Em-dash separator in titles: `"\(project) — \(branch)"` (same "—" used elsewhere in the app).
- Run tests with `swift test 2>&1 | grep -E "Executed [0-9]+ tests"` (trust XCTest lines; SourceKit diagnostics go stale — ignore them).

---

### Task 1: Git branch discovery (`gitBranch(forCwd:)`)

**Files:**
- Create: `Sources/ClaudeLightCore/GitBranch.swift`
- Test: `Tests/ClaudeLightCoreTests/GitBranchTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public func gitBranch(forCwd cwd: String) -> String?` — nil for empty cwd, non-repos, detached HEAD, malformed layouts. Internal helpers `parseGitHead(_ contents: String) -> String?` and `resolveGitdirFile(_ file: URL) -> URL?` (testable via `@testable import`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ClaudeLightCore

final class GitBranchTests: XCTestCase {
    // MARK: – parseGitHead

    func test_parseHead_normalRef() {
        XCTAssertEqual(parseGitHead("ref: refs/heads/main\n"), "main")
    }

    func test_parseHead_nestedBranchName_slashesPreserved() {
        XCTAssertEqual(parseGitHead("ref: refs/heads/feat/branch-labels\n"), "feat/branch-labels")
    }

    func test_parseHead_detachedSHA_isNil() {
        XCTAssertNil(parseGitHead("2e117d43b3bd541e5d5a0a77e58c2d78784ee283\n"))
    }

    func test_parseHead_malformed_isNil() {
        XCTAssertNil(parseGitHead("ref: refs/tags/v1.0\n"))
        XCTAssertNil(parseGitHead(""))
        XCTAssertNil(parseGitHead("ref: refs/heads/\n"))
    }

    // MARK: – discovery fixtures

    /// Builds a fake repo layout under a unique tmp root; returns the root.
    private func makeTree(_ files: [String: String], dirs: [String] = []) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-light-git-\(UUID().uuidString)")
        for dir in dirs {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    func test_branch_atRepoRoot() throws {
        let root = try makeTree(["repo/.git/HEAD": "ref: refs/heads/main\n"])
        XCTAssertEqual(gitBranch(forCwd: root.appendingPathComponent("repo").path), "main")
    }

    func test_branch_fromNestedSubdirectory() throws {
        let root = try makeTree(["repo/.git/HEAD": "ref: refs/heads/fix/x\n"],
                                dirs: ["repo/Sources/Deep"])
        XCTAssertEqual(gitBranch(forCwd: root.appendingPathComponent("repo/Sources/Deep").path),
                       "fix/x")
    }

    func test_nonRepo_isNil() throws {
        let root = try makeTree([:], dirs: ["plain/dir"])
        XCTAssertNil(gitBranch(forCwd: root.appendingPathComponent("plain/dir").path))
    }

    func test_worktree_gitdirFile_absolutePath() throws {
        let root = try makeTree([:], dirs: ["wt"])
        let gitdir = try makeTree(["worktrees/wt/HEAD": "ref: refs/heads/feat/wt\n"])
        try "gitdir: \(gitdir.appendingPathComponent("worktrees/wt").path)\n"
            .write(to: root.appendingPathComponent("wt/.git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(gitBranch(forCwd: root.appendingPathComponent("wt").path), "feat/wt")
    }

    func test_worktree_gitdirFile_relativePath() throws {
        let root = try makeTree(["actual/HEAD": "ref: refs/heads/rel\n"], dirs: ["wt"])
        try "gitdir: ../actual\n"
            .write(to: root.appendingPathComponent("wt/.git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(gitBranch(forCwd: root.appendingPathComponent("wt").path), "rel")
    }

    func test_missingHEAD_isNil() throws {
        let root = try makeTree([:], dirs: ["repo/.git"])
        XCTAssertNil(gitBranch(forCwd: root.appendingPathComponent("repo").path))
    }

    func test_emptyCwd_isNil() {
        XCTAssertNil(gitBranch(forCwd: ""))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GitBranchTests 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'parseGitHead' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Branch name for the git checkout containing `cwd`, or nil for non-repos,
/// detached HEAD, and unreadable layouts. Walks parents to the nearest
/// `.git`, then reads HEAD directly — one file read per level, never a
/// subprocess (hook perf, #43).
public func gitBranch(forCwd cwd: String) -> String? {
    guard !cwd.isEmpty else { return nil }
    var dir = URL(fileURLWithPath: cwd).standardizedFileURL
    while true {
        let dotGit = dir.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
            // A `.git` FILE marks a worktree/submodule: follow its gitdir pointer.
            guard let gitDir = isDir.boolValue ? dotGit : resolveGitdirFile(dotGit),
                  let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"),
                                         encoding: .utf8)
            else { return nil }
            return parseGitHead(head)
        }
        if dir.path == "/" { return nil }
        dir = dir.deletingLastPathComponent()
    }
}

/// "ref: refs/heads/<branch>" → branch (slashes preserved). Anything else —
/// detached SHA, tag ref, empty — is nil.
func parseGitHead(_ contents: String) -> String? {
    let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "ref: refs/heads/"
    guard line.hasPrefix(prefix) else { return nil }
    let name = String(line.dropFirst(prefix.count))
    return name.isEmpty ? nil : name
}

/// A worktree/submodule `.git` file holds "gitdir: <path>"; relative paths
/// resolve against the file's directory.
func resolveGitdirFile(_ file: URL) -> URL? {
    guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
    let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    guard line.hasPrefix("gitdir:") else { return nil }
    let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
    guard !path.isEmpty else { return nil }
    if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
    return URL(fileURLWithPath: path, relativeTo: file.deletingLastPathComponent())
        .standardizedFileURL
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GitBranchTests 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: `Executed 11 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/GitBranch.swift Tests/ClaudeLightCoreTests/GitBranchTests.swift
git commit -m "feat: git branch discovery from cwd — direct HEAD read, no subprocess (#82)"
```

---

### Task 2: `branch` on the Session schema

**Files:**
- Modify: `Sources/ClaudeLightCore/Session.swift` (property list ~line 31, init ~lines 33–49, CodingKeys ~lines 51–64)
- Test: `Tests/ClaudeLightCoreTests/SessionTests.swift` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: `Session.branch: String?`, JSON key `"branch"`, init parameter `branch: String? = nil` placed after `contextFraction`.

- [ ] **Step 1: Write the failing tests** (append to `SessionTests.swift`)

```swift
    func test_branch_roundTrips() throws {
        let s = Session(sessionID: "b1", status: .running, project: "p", cwd: "/x",
                        updatedAt: Date(timeIntervalSince1970: 1_719_745_200),
                        branch: "feat/labels")
        let data = try ClaudeLightJSON.encoder.encode(s)
        let back = try ClaudeLightJSON.decoder.decode(Session.self, from: data)
        XCTAssertEqual(back.branch, "feat/labels")
    }

    func test_sessionJSON_withoutBranchKey_decodes() throws {
        let json = #"{"session_id":"b2","status":"idle","project":"p","cwd":"/x","updated_at":"2026-07-05T08:00:00Z"}"#
        let s = try ClaudeLightJSON.decoder.decode(Session.self, from: Data(json.utf8))
        XCTAssertNil(s.branch)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionTests 2>&1 | tail -5`
Expected: compile FAILURE — `extra argument 'branch' in call` / `value of type 'Session' has no member 'branch'`.

- [ ] **Step 3: Add the property, init parameter, and CodingKey**

In the property block, after `contextFraction`:

```swift
    /// Git branch of the session's cwd at the last hook event (#82); nil for
    /// non-repos, detached HEAD, and sessions written by older hooks.
    public var branch: String?
```

Init signature gains `branch: String? = nil` after `contextFraction: Double? = nil`, and the body gains `self.branch = branch`. CodingKeys gains `case branch` (key name matches, no raw value needed).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionTests 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: all SessionTests pass, including the two new ones.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/Session.swift Tests/ClaudeLightCoreTests/SessionTests.swift
git commit -m "feat: persist git branch in the session schema (#82)"
```

---

### Task 3: Wire discovery into `applyHook`

**Files:**
- Modify: `Sources/ClaudeLightCore/ApplyHook.swift` (Session construction, ~lines 15–32)
- Test: `Tests/ClaudeLightCoreTests/ApplyHookTests.swift` (append)

**Interfaces:**
- Consumes: `gitBranch(forCwd:)` (Task 1), `Session.branch` (Task 2).
- Produces: session files whose `branch` obeys the merge semantics in Global Constraints.

- [ ] **Step 1: Write the failing tests** (append inside `ApplyHookTests`; the class already has `tempStore()` and `now` — see its head)

```swift
    // MARK: – Branch labels (#82)

    /// A minimal on-disk repo: <root>/repo/.git/HEAD on the given ref line.
    private func makeRepo(head: String) throws -> String {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-light-apply-repo-\(UUID().uuidString)/repo")
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try head.write(to: repo.appendingPathComponent(".git/HEAD"),
                       atomically: true, encoding: .utf8)
        return repo.path
    }

    func test_applyHook_capturesBranch_fromRepoCwd() throws {
        let store = tempStore()
        let repo = try makeRepo(head: "ref: refs/heads/feat/labels\n")
        let p = HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: repo, message: nil)
        try applyHook(p, to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.branch, "feat/labels")
    }

    func test_applyHook_freshReadWins_detachedClearsBranch() throws {
        let store = tempStore()
        let repo = try makeRepo(head: "ref: refs/heads/main\n")
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: repo, message: nil),
                      to: store, now: now)
        try "2e117d43b3bd541e5d5a0a77e58c2d78784ee283\n"
            .write(to: URL(fileURLWithPath: repo).appendingPathComponent(".git/HEAD"),
                   atomically: true, encoding: .utf8)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: repo, message: nil),
                      to: store, now: now)
        XCTAssertNil(try store.loadAll().first?.branch)
    }

    func test_applyHook_keepsBranch_whenPayloadHasNoCwd() throws {
        let store = tempStore()
        let repo = try makeRepo(head: "ref: refs/heads/main\n")
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: repo, message: nil),
                      to: store, now: now)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: nil, message: nil),
                      to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.branch, "main")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ApplyHookTests 2>&1 | tail -5`
Expected: the three new tests FAIL (`XCTAssertEqual failed: ("nil") is not equal to ("Optional("feat/labels")")` etc.); existing ones pass.

- [ ] **Step 3: Wire the branch into the Session construction**

In `applyHook`, add to the `Session(...)` call after the `contextFraction:` argument:

```swift
            // Branch refreshes whenever the event carries a cwd — a nil read
            // (detached HEAD, repo gone) clears the label. cwd-less events
            // keep the last value, like contextFraction (#82).
            branch: payload.cwd != nil ? gitBranch(forCwd: cwd) : existing?.branch
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ApplyHookTests 2>&1 | grep -E "Executed [0-9]+ tests"`
Expected: all ApplyHookTests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/ApplyHook.swift Tests/ClaudeLightCoreTests/ApplyHookTests.swift
git commit -m "feat: hook captures the cwd's git branch on every event (#82)"
```

---

### Task 4: Render `project — branch` in display names

**Files:**
- Modify: `Sources/ClaudeLightCore/HeadlessSessions.swift:16-19` (`displayName(for:)`)
- Test: `Tests/ClaudeLightCoreTests/HeadlessSessionTests.swift` (append)

**Interfaces:**
- Consumes: `Session.branch` (Task 2).
- Produces: `displayName(for:)` returning `"project — branch"` / `"project — branch (background)"`. Card titles, VoiceOver labels, and notification titles all flow through this one function — no other UI change.

- [ ] **Step 1: Write the failing tests** (append; the file's `session(...)` helper needs a `branch` parameter — extend it with `branch: String? = nil` passed through to the `Session` init)

```swift
    func test_displayName_appendsBranch() {
        XCTAssertEqual(displayName(for: session("a", .running, tty: "ttys006", branch: "feat/x")),
                       "p — feat/x")
    }

    func test_displayName_branchThenBackgroundSuffix() {
        XCTAssertEqual(displayName(for: session("a", .running, branch: "main")),
                       "p — main (background)")
    }

    func test_displayName_noBranch_unchanged() {
        XCTAssertEqual(displayName(for: session("a", .running, tty: "ttys006")), "p")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HeadlessSessionTests 2>&1 | tail -5`
Expected: compile FAILURE on the helper (`extra argument 'branch'`) until it's extended, then assertion failures for the two new expectations.

- [ ] **Step 3: Implement**

```swift
/// Row title for a session: "project — branch" when the cwd sits on a git
/// branch (#82), with headless runs marked.
public func displayName(for session: Session) -> String {
    let base = session.branch.map { "\(session.project) — \($0)" } ?? session.project
    return isHeadless(session) ? "\(base) (background)" : base
}
```

- [ ] **Step 4: Run the full suite**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: all tests pass (249 pre-existing + 19 new = 268; count may drift, zero failures is the gate).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/HeadlessSessions.swift Tests/ClaudeLightCoreTests/HeadlessSessionTests.swift
git commit -m "feat: session titles show the cwd's git branch (#82)"
```

---

### Task 5: Live end-to-end verification

**Files:** none (build + manual verification).

**Interfaces:**
- Consumes: everything above.
- Produces: user-verified panel behavior; PR.

- [ ] **Step 1: Build, sign, and swap the local app** (both binaries change: app renders, hook writes)

```bash
./scripts/package-app.sh
codesign --force --options runtime --sign "Developer ID Application: Fernando Castillo (7MTZYB93KB)" "dist/Claude Light.app/Contents/MacOS/claude-light-hook"
codesign --force --options runtime --sign "Developer ID Application: Fernando Castillo (7MTZYB93KB)" "dist/Claude Light.app/Contents/MacOS/ClaudeLightApp"
codesign --force --options runtime --sign "Developer ID Application: Fernando Castillo (7MTZYB93KB)" "dist/Claude Light.app"
osascript -e 'tell application "Claude Light" to quit'; sleep 1
rm -rf "/Applications/Claude Light.app" && cp -R "dist/Claude Light.app" "/Applications/Claude Light.app"
open "/Applications/Claude Light.app"
```

- [ ] **Step 2: Verify live** — the working session (this repo, on `feat/branch-labels`) titles as "claude-light — feat/branch-labels" after its next hook event. Seed a non-repo demo session (must carry `term_program`/`tty` or the headless filter hides it) and confirm it shows no branch:

```bash
printf '{"cwd":"/tmp","updated_at":"%s","project":"no-repo-demo","session_id":"no-repo-demo","status":"idle","term_program":"WarpTerminal","tty":"ttys099"}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > ~/.claude-light/sessions/no-repo-demo.json
```

Ask the user to confirm both cards, then clean up: `rm ~/.claude-light/sessions/no-repo-demo.json`

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin feat/branch-labels
gh pr create --title "feat: session titles show the cwd's git branch (#82)" --body "..."
```

PR body summarizes: hook-side HEAD read (no subprocess, #43), worktree `gitdir:` support, merge semantics (fresh-read-wins with cwd, survives cwd-less events), `displayName` rendering, test counts, live verification. Closes #82.
