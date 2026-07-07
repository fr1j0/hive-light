# Dangling Worktree Root — Design

**Date:** 2026-07-07
**Status:** Approved (found while root-causing the two-blocks-one-project
report; the claude-light → hive-light folder rename left a worktree whose
absolute gitdir pointer referenced the dead old path)

## Problem

`gitRepoRoot(forCwd:)` (`GitBranch.swift`) derives a worktree's grouping
identity by string-parsing the `.git` file's `gitdir:` pointer — without
checking that the target exists. Git worktree pointers are absolute paths,
so renaming the parent repo folder leaves them dangling; the function then
stamps a nonexistent path as `repo_root`, and the panel groups the session
under a phantom project named after the dead folder (e.g. `CLAUDE-LIGHT`
after the rename), separate from the real checkout's group.

## Change

One guard in `gitRepoRoot`: after `resolveGitdirFile` produces the gitdir
URL, verify the target exists on disk. If it does not, return `dir.path`
(the checkout directory itself) — the same fallback the function already
uses for unrecognized layouts. The session then groups honestly under its
own folder instead of a phantom path.

`gitBranch` shares the trust but not the harm (a dangling gitdir yields a
nil branch, which the UI already handles) — out of scope.

## Behavior matrix

- Healthy worktree: unchanged — unifies with the main repo.
- Dangling gitdir (renamed/deleted parent): `repo_root` = the worktree
  checkout dir; the block header is the worktree folder name. Honest,
  self-describing, and self-heals the moment `git worktree repair` runs.
- Non-repos, normal repos, relative gitdir pointers: unchanged.

## Testing

TDD in `Tests/HiveLightCoreTests/GitBranchTests.swift` using the existing
`makeTree` fixtures: a worktree `.git` file pointing at a nonexistent
absolute `<gone>/.git/worktrees/<name>` path must yield the checkout dir,
not the dead prefix. Existing worktree-unification tests must stay green.
