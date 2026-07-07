# Dangling Worktree Root Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `gitRepoRoot` from trusting dangling worktree gitdir pointers — fall back to the checkout dir so sessions never group under a phantom dead path.

**Architecture:** One existence guard in `gitRepoRoot` (`GitBranch.swift`), TDD-first with the existing `makeTree` fixture helpers in `GitBranchTests.swift`.

**Tech Stack:** Swift/SwiftPM, XCTest.

**Spec:** `docs/superpowers/specs/2026-07-07-dangling-worktree-root-design.md`

## Global Constraints

- Fallback for a dangling gitdir is exactly `dir.path` (the checkout dir), matching the existing unrecognized-layout fallback.
- Healthy-worktree unification, normal repos, relative gitdir pointers, and non-repos behave exactly as before — all existing tests stay green.
- `gitBranch` is out of scope.
- Work happens on branch `fix/dangling-worktree-root` (already created, spec committed).

---

### Task 1: Existence guard, TDD

**Files:**
- Test: `Tests/HiveLightCoreTests/GitBranchTests.swift` (add one test near the existing `test_repoRoot_worktree_unifiesWithMainRepo`)
- Modify: `Sources/HiveLightCore/GitBranch.swift:41-45` (inside `gitRepoRoot`)

**Interfaces:**
- Consumes: existing `makeTree(_:dirs:)` test helper; `resolveGitdirFile(_:)`.
- Produces: no signature changes — behavior fix only.

- [ ] **Step 1: Write the failing test**

Add to `GitBranchTests.swift`, after `test_repoRoot_worktree_unifiesWithMainRepo`:

```swift
    func test_repoRoot_danglingWorktreeGitdir_fallsBackToCheckoutDir() throws {
        // Renaming a repo folder leaves worktree gitdir pointers (absolute
        // paths) dangling. Trusting the dead string would group the session
        // under a phantom path — fall back to the checkout itself.
        let root = try makeTree([:], dirs: ["wt"])
        try "gitdir: \(root.appendingPathComponent("gone/.git/worktrees/wt").path)\n"
            .write(to: root.appendingPathComponent("wt/.git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(gitRepoRoot(forCwd: root.appendingPathComponent("wt").path),
                       root.appendingPathComponent("wt").path)
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter test_repoRoot_danglingWorktreeGitdir 2>&1 | tail -5`
Expected: FAIL — the current code returns the dead `<root>/gone` prefix, not the checkout dir.

- [ ] **Step 3: Implement the guard**

In `Sources/HiveLightCore/GitBranch.swift`, `gitRepoRoot`, replace:

```swift
            guard let gitDir = resolveGitdirFile(dotGit) else { return dir.path }
            let path = gitDir.standardizedFileURL.path
```

with:

```swift
            guard let gitDir = resolveGitdirFile(dotGit) else { return dir.path }
            // Worktree gitdir pointers are absolute paths; renaming the
            // parent repo folder leaves them dangling. A dead pointer must
            // not become the grouping key — fall back to this checkout.
            guard FileManager.default.fileExists(atPath: gitDir.standardizedFileURL.path) else {
                return dir.path
            }
            let path = gitDir.standardizedFileURL.path
```

- [ ] **Step 4: Run the new test and the full suite**

Run: `swift test --filter GitBranchTests 2>&1 | tail -3` then `swift test 2>&1 | grep -E "Test Suite 'All tests' (passed|failed)" | tail -1`
Expected: new test passes; all suites pass (no existing worktree/normal-repo test regresses).

- [ ] **Step 5: Commit**

```bash
git add Tests/HiveLightCoreTests/GitBranchTests.swift Sources/HiveLightCore/GitBranch.swift
git commit -m "fix: never group sessions under a dangling worktree gitdir"
```

---

### Task 2: Live sanity + PR (no deploy ritual needed)

This fix has no visible UI on a healthy machine (the local dangling worktree was already repaired), so the live-check deploy is skipped; the TDD fixture is the reproduction. Push and open the PR:

- [ ] **Step 1: Push and open PR**

```bash
git push -u origin fix/dangling-worktree-root
gh pr create --title "fix: never group sessions under a dangling worktree gitdir" \
  --body "gitRepoRoot string-parsed the worktree gitdir pointer without checking it exists; a parent-folder rename (claude-light → hive-light) left absolute pointers dangling and sessions grouped under a phantom dead path. One existence guard: dangling pointer → fall back to the checkout dir (same fallback as unrecognized layouts). TDD fixture reproduces the rename scenario; healthy-worktree unification unchanged."
```
